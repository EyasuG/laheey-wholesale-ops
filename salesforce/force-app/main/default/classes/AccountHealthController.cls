/**
 * Level 5. Backs the accountHealthCard LWC on the Account record page.
 */
public with sharing class AccountHealthController {

    public class MonthPoint {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Decimal orders;
    }

    public class HealthView {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String warehouseId;
        @AuraEnabled public Decimal lifetimeRevenue;
        @AuraEnabled public Decimal revenue12m;
        @AuraEnabled public Date lastOrderDate;
        @AuraEnabled public Decimal openCases;
        @AuraEnabled public Datetime lastSynced;
        @AuraEnabled public AccountHealthService.Result health;
        @AuraEnabled public List<MonthPoint> months = new List<MonthPoint>();
    }

    @AuraEnabled(cacheable=true)
    public static HealthView getHealth(Id accountId) {
        Account a = [
            SELECT Id, Warehouse_Id__c, Lifetime_Revenue__c, Revenue_12M__c, Last_Order_Date__c, Open_Cases__c, Last_Synced__c
            FROM Account WHERE Id = :accountId WITH USER_MODE
        ];
        Date today = Date.today();
        HealthView v = new HealthView();
        v.accountId = a.Id;
        v.warehouseId = a.Warehouse_Id__c;
        v.lifetimeRevenue = a.Lifetime_Revenue__c;
        v.revenue12m = a.Revenue_12M__c;
        v.lastOrderDate = a.Last_Order_Date__c;
        v.openCases = a.Open_Cases__c;
        v.lastSynced = a.Last_Synced__c;

        Decimal[] w = AccountHealthService.revenueWindows(new Set<Id>{ a.Id }, today).get(a.Id);
        v.health = AccountHealthService.score(a.Last_Order_Date__c, w[0], w[1], a.Open_Cases__c, today);

        for (Account_Metric__c m : [
            SELECT Month__c, Revenue__c, Order_Count__c
            FROM Account_Metric__c
            WHERE Account__c = :accountId AND Month__c >= :today.toStartOfMonth().addMonths(-11)
            WITH USER_MODE
            ORDER BY Month__c
        ]) {
            MonthPoint p = new MonthPoint();
            p.label = Datetime.newInstance(m.Month__c, Time.newInstance(12, 0, 0, 0)).format('MMM yy');
            p.revenue = m.Revenue__c;
            p.orders = m.Order_Count__c;
            v.months.add(p);
        }
        return v;
    }

    /** Live callout: pulls fresh numbers for one account and saves them. Callout first, then DML. */
    @AuraEnabled
    public static String refreshFromWarehouse(Id accountId) {
        Account a = [SELECT Id, Warehouse_Id__c FROM Account WHERE Id = :accountId WITH USER_MODE];
        if (String.isBlank(a.Warehouse_Id__c)) {
            throw newError('This account is not linked to the warehouse (no Warehouse Id).');
        }
        WarehouseClient.AccountSummary s;
        try {
            s = WarehouseClient.getAccountSummary(a.Warehouse_Id__c);
        } catch (Exception e) {
            throw newError('Could not reach the warehouse: ' + e.getMessage());
        }
        if (s == null) {
            throw newError('The warehouse has no account ' + a.Warehouse_Id__c + '.');
        }
        Account upd = new Account(
            Id = a.Id,
            Lifetime_Revenue__c = s.lifetimeRevenue,
            Revenue_12M__c = s.revenue12m,
            Orders_Last_90_Days__c = s.orders90d,
            Last_Order_Date__c = s.lastOrderDate,
            Open_Cases__c = s.openCases,
            Last_Synced__c = System.now()
        );
        update as user upd;
        return 'Refreshed from the warehouse: ' + s.orders90d + ' orders in the last 90 days, ' + s.openCases + ' open cases.';
    }

    private static AuraHandledException newError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);   // so tests and logs see the real text
        return e;
    }
}
