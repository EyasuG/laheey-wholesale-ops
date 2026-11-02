/**
 * Level 3. Recalculates Subtotal__c and Line_Count__c on the parent Wholesale_Order__c whenever lines change.
 *
 * Why not a roll-up summary field? Orders synced from the warehouse carry their subtotal without lines
 * (lines stay in the warehouse to save storage). A roll-up would overwrite that with 0. This rollup only
 * runs for orders whose lines were edited in Salesforce, so synced subtotals are left alone.
 *
 * Why sum in Apex and not SUM() in SOQL? Line_Total__c is a formula, and formula fields can't be aggregated.
 */
public with sharing class OrderLineRollup {

    public static void recalculate(List<Order_Line__c> lines, Map<Id, Order_Line__c> oldMap) {
        Set<Id> orderIds = new Set<Id>();
        for (Order_Line__c line : lines) {
            orderIds.add(line.Wholesale_Order__c);
            // A line moved to another order: recalculate the old parent too
            if (oldMap != null && oldMap.containsKey(line.Id)) {
                orderIds.add(oldMap.get(line.Id).Wholesale_Order__c);
            }
        }
        orderIds.remove(null);
        if (orderIds.isEmpty()) {
            return;
        }

        Map<Id, Wholesale_Order__c> updates = new Map<Id, Wholesale_Order__c>();
        for (Id orderId : orderIds) {
            updates.put(orderId, new Wholesale_Order__c(Id = orderId, Subtotal__c = 0, Line_Count__c = 0));
        }
        // One query for every affected order, however many lines changed
        for (Order_Line__c line : [
            SELECT Wholesale_Order__c, Quantity__c, Unit_Price__c
            FROM Order_Line__c
            WHERE Wholesale_Order__c IN :orderIds
        ]) {
            Wholesale_Order__c o = updates.get(line.Wholesale_Order__c);
            Decimal qty = line.Quantity__c == null ? 0 : line.Quantity__c;
            Decimal price = line.Unit_Price__c == null ? 0 : line.Unit_Price__c;
            o.Subtotal__c += (qty * price).setScale(2);
            o.Line_Count__c += 1;
        }
        update updates.values();   // fires WholesaleOrderTrigger, which recalculates Total__c
    }
}
