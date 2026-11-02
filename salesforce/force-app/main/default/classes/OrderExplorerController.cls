/**
 * Level 5-6. Backs the orderExplorer LWC: an account's order history with infinite scrolling.
 *
 * Uses keyset pagination (WHERE (date, id) < (last date, last id)) instead of OFFSET:
 * OFFSET is capped at 2,000 rows in SOQL and gets slower the deeper you page; a keyset
 * query costs the same on page 1 and page 500. The same pattern is used in the warehouse API.
 */
public with sharing class OrderExplorerController {

    @AuraEnabled(cacheable=true)
    public static List<Wholesale_Order__c> getOrders(Id accountId, Date beforeDate, Id beforeId, Integer pageSize) {
        Integer size = (pageSize == null || pageSize < 1 || pageSize > 200) ? 50 : pageSize;
        if (beforeDate == null) {
            return [
                SELECT Id, Name, Order_Date__c, Ship_Date__c, Status__c, Payment_Status__c, Channel__c, Total__c, Line_Count__c
                FROM Wholesale_Order__c
                WHERE Account__c = :accountId
                WITH USER_MODE
                ORDER BY Order_Date__c DESC, Id DESC
                LIMIT :size
            ];
        }
        return [
            SELECT Id, Name, Order_Date__c, Ship_Date__c, Status__c, Payment_Status__c, Channel__c, Total__c, Line_Count__c
            FROM Wholesale_Order__c
            WHERE Account__c = :accountId
              AND (Order_Date__c < :beforeDate OR (Order_Date__c = :beforeDate AND Id < :beforeId))
            WITH USER_MODE
            ORDER BY Order_Date__c DESC, Id DESC
            LIMIT :size
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSummary(Id accountId) {
        AggregateResult ar = [
            SELECT COUNT(Id) orders, SUM(Total__c) revenue
            FROM Wholesale_Order__c
            WHERE Account__c = :accountId AND Status__c != 'Cancelled'
            WITH USER_MODE
        ];
        Integer overdue = [
            SELECT COUNT() FROM Wholesale_Order__c
            WHERE Account__c = :accountId AND Payment_Status__c = 'Overdue'
            WITH USER_MODE
        ];
        return new Map<String, Object>{
            'orders' => ar.get('orders'),
            'revenue' => ar.get('revenue'),
            'overdue' => overdue
        };
    }
}
