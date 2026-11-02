/**
 * Builds test records. Every test creates its own data (no SeeAllData), so tests pass in any org.
 */
@IsTest
public class TestDataFactory {

    public static List<Account> accounts(Integer count) {
        List<Account> rows = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            rows.add(new Account(
                Name = 'Test Cafe ' + i,
                Warehouse_Id__c = 'ACC-' + String.valueOf(9000000 + i),
                Segment__c = 'Cafe',
                Tier__c = 'Gold',
                Last_Order_Date__c = Date.today().addDays(-5),
                Open_Cases__c = 0,
                Revenue_12M__c = 12000
            ));
        }
        insert rows;
        return rows;
    }

    public static List<Wholesale_Order__c> orders(Id accountId, Integer count, String status) {
        List<Wholesale_Order__c> rows = new List<Wholesale_Order__c>();
        for (Integer i = 0; i < count; i++) {
            rows.add(new Wholesale_Order__c(
                Name = 'LWO-T' + String.valueOf(1000000 + i) + String.valueOf(accountId).right(4),
                Account__c = accountId,
                Order_Date__c = Date.today().addDays(-i),
                Status__c = status,
                Payment_Status__c = 'Invoiced',
                Channel__c = 'Sales Rep',
                Subtotal__c = 100,
                Discount__c = 0,
                Shipping__c = 25
            ));
        }
        insert rows;
        return rows;
    }

    /**
     * A sales/ops user with Laheey_Wholesale_Ops only. Use with System.runAs when a test needs the
     * business rules enforced: the admin running tests may also hold Laheey_Integration, whose
     * Bypass_Order_Status_Rules custom permission switches the status rule off.
     */
    public static User opsUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@laheey.test';
        User u = new User(
            ProfileId = p.Id, Username = 'ops' + unique, Email = 'ops' + unique, LastName = 'Ops', Alias = 'lops',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert u;
        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Laheey_Wholesale_Ops' LIMIT 1].Id
        );
        return u;
    }

    /** Six months of metrics: the three older months at priorRevenue, the three recent ones at recentRevenue. */
    public static void metrics(Id accountId, Decimal recentRevenue, Decimal priorRevenue) {
        List<Account_Metric__c> rows = new List<Account_Metric__c>();
        Date thisMonth = Date.today().toStartOfMonth();
        for (Integer i = 0; i < 6; i++) {
            Date month = thisMonth.addMonths(-i);
            rows.add(new Account_Metric__c(
                Name = String.valueOf(month).left(7),
                Account__c = accountId,
                Warehouse_Id__c = String.valueOf(accountId) + '-' + i,
                Month__c = month,
                Revenue__c = i < 3 ? recentRevenue : priorRevenue,
                Order_Count__c = 10
            ));
        }
        insert rows;
    }
}
