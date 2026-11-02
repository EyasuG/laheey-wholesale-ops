/**
 * Level 3. Business rules for Wholesale_Order__c, bulk-safe (no SOQL or DML in loops).
 *  - Total = Subtotal - Discount + Shipping, on every insert and update.
 *  - Status may only move forward: Placed > Roasting > Shipped > Delivered (or Cancelled before shipping).
 *  - Moving to Shipped stamps a ship date when none is set.
 * Integration users skip the status rule (custom permission Bypass_Order_Status_Rules),
 * because the warehouse is the source of truth and a synced order can jump several steps between syncs.
 */
public with sharing class WholesaleOrderTriggerHandler {

    @TestVisible
    private static final Map<String, Set<String>> ALLOWED_NEXT = new Map<String, Set<String>>{
        'Placed' => new Set<String>{ 'Roasting', 'Cancelled' },
        'Roasting' => new Set<String>{ 'Shipped', 'Cancelled' },
        'Shipped' => new Set<String>{ 'Delivered' },
        'Delivered' => new Set<String>(),
        'Cancelled' => new Set<String>()
    };

    /** Set by WarehouseSyncJob for the duration of its upsert. */
    public static Boolean bypassStatusRules = false;

    public static void handle(System.TriggerOperation operation, List<Wholesale_Order__c> newOrders, Map<Id, Wholesale_Order__c> oldMap) {
        switch on operation {
            when BEFORE_INSERT {
                calculateTotals(newOrders);
            }
            when BEFORE_UPDATE {
                enforceStatusFlow(newOrders, oldMap);
                calculateTotals(newOrders);
            }
            when else {
                return;
            }
        }
    }

    @TestVisible
    private static void calculateTotals(List<Wholesale_Order__c> orders) {
        for (Wholesale_Order__c o : orders) {
            Decimal subtotal = o.Subtotal__c == null ? 0 : o.Subtotal__c;
            Decimal discount = o.Discount__c == null ? 0 : o.Discount__c;
            Decimal shipping = o.Shipping__c == null ? 0 : o.Shipping__c;
            o.Total__c = (subtotal - discount + shipping).setScale(2);
        }
    }

    private static void enforceStatusFlow(List<Wholesale_Order__c> orders, Map<Id, Wholesale_Order__c> oldMap) {
        Boolean bypass = bypassStatusRules || FeatureManagement.checkPermission('Bypass_Order_Status_Rules');
        for (Wholesale_Order__c o : orders) {
            Wholesale_Order__c before = oldMap.get(o.Id);
            if (o.Status__c == before.Status__c) {
                continue;
            }
            Set<String> allowed = ALLOWED_NEXT.get(before.Status__c);
            if (!bypass && allowed != null && !allowed.contains(o.Status__c)) {
                o.Status__c.addError('An order can\'t move from ' + before.Status__c + ' to ' + o.Status__c + '.');
                continue;
            }
            if (o.Status__c == 'Shipped' && o.Ship_Date__c == null) {
                o.Ship_Date__c = Date.today();
            }
        }
    }
}
