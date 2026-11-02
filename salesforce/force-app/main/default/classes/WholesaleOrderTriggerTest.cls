@IsTest
private class WholesaleOrderTriggerTest {

    @TestSetup
    static void setup() {
        TestDataFactory.accounts(1);
    }

    @IsTest
    static void calculatesTotalsForABulkInsert() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        TestDataFactory.orders(a.Id, 200, 'Placed');   // one full trigger chunk
        Test.stopTest();
        for (Wholesale_Order__c o : [SELECT Total__c FROM Wholesale_Order__c]) {
            Assert.areEqual(125.00, o.Total__c, 'Total = 100 subtotal - 0 discount + 25 shipping');
        }
    }

    @IsTest
    static void allowsForwardStatusChangesAndStampsShipDate() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Wholesale_Order__c o = TestDataFactory.orders(a.Id, 1, 'Roasting')[0];
        o.Status__c = 'Shipped';
        update o;
        o = [SELECT Status__c, Ship_Date__c FROM Wholesale_Order__c WHERE Id = :o.Id];
        Assert.areEqual('Shipped', o.Status__c);
        Assert.areEqual(Date.today(), o.Ship_Date__c, 'Ship date is stamped when an order ships');
    }

    @IsTest
    static void blocksBackwardStatusChanges() {
        // Run as an ops user: the admin may hold the integration bypass, which would skip the rule under test
        System.runAs(TestDataFactory.opsUser()) {
            Account a = new Account(Name = 'Ops Test Cafe');
            insert a;
            Wholesale_Order__c o = TestDataFactory.orders(a.Id, 1, 'Delivered')[0];
            o.Status__c = 'Placed';
            Database.SaveResult sr = Database.update(o, false);
            Assert.isFalse(sr.isSuccess(), 'Delivered orders cannot go back to Placed');
            Assert.isTrue(sr.getErrors()[0].getMessage().contains('Delivered to Placed'), sr.getErrors()[0].getMessage());
        }
    }

    @IsTest
    static void syncBypassLetsTheWarehouseSkipSteps() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Wholesale_Order__c o = TestDataFactory.orders(a.Id, 1, 'Placed')[0];
        WholesaleOrderTriggerHandler.bypassStatusRules = true;
        o.Status__c = 'Delivered';
        update o;
        Assert.areEqual('Delivered', [SELECT Status__c FROM Wholesale_Order__c WHERE Id = :o.Id].Status__c);
    }

    @IsTest
    static void validationRuleRejectsShipBeforeOrder() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Wholesale_Order__c o = new Wholesale_Order__c(Name = 'LWO-VR1', Account__c = a.Id, Order_Date__c = Date.today(),
            Ship_Date__c = Date.today().addDays(-1), Status__c = 'Shipped', Payment_Status__c = 'Paid', Channel__c = 'Phone');
        Database.SaveResult sr = Database.insert(o, false);
        Assert.isFalse(sr.isSuccess());
    }
}
