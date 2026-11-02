@IsTest
private class ControllersTest {

    @TestSetup
    static void setup() {
        Account a = TestDataFactory.accounts(1)[0];
        TestDataFactory.metrics(a.Id, 3000, 2500);
        TestDataFactory.orders(a.Id, 120, 'Delivered');
    }

    @IsTest
    static void healthViewIncludesScoreAndMonths() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        AccountHealthController.HealthView v = AccountHealthController.getHealth(a.Id);
        Assert.areEqual('Healthy', v.health.status);
        Assert.areEqual(6, v.months.size());
        Assert.isNotNull(v.months[0].label);
    }

    @IsTest
    static void refreshCallsTheWarehouseAndSaves() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new WarehouseHttpMock());
        Test.startTest();
        String msg = AccountHealthController.refreshFromWarehouse(a.Id);
        Test.stopTest();
        Assert.isTrue(msg.contains('21 orders'), msg);
        a = [SELECT Orders_Last_90_Days__c, Open_Cases__c, Last_Synced__c FROM Account WHERE Id = :a.Id];
        Assert.areEqual(21, a.Orders_Last_90_Days__c);
        Assert.areEqual(2, a.Open_Cases__c);
        Assert.isNotNull(a.Last_Synced__c);
    }

    @IsTest
    static void refreshReportsAMissingWarehouseAccount() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        update new Account(Id = a.Id, Warehouse_Id__c = 'ACC-MISSING');
        Test.setMock(HttpCalloutMock.class, new WarehouseHttpMock());
        Test.startTest();   // new transaction: no callouts after uncommitted DML
        try {
            AccountHealthController.refreshFromWarehouse(a.Id);
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('no account'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void keysetPagingWalksEveryOrderOnce() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Set<Id> seen = new Set<Id>();
        Date beforeDate = null;
        Id beforeId = null;
        Integer pages = 0;
        while (true) {
            List<Wholesale_Order__c> page = OrderExplorerController.getOrders(a.Id, beforeDate, beforeId, 50);
            if (page.isEmpty()) { break; }
            for (Wholesale_Order__c o : page) {
                Assert.isFalse(seen.contains(o.Id), 'No order appears twice');
                seen.add(o.Id);
            }
            Wholesale_Order__c last = page[page.size() - 1];
            beforeDate = last.Order_Date__c;
            beforeId = last.Id;
            pages++;
        }
        Assert.areEqual(120, seen.size());
        Assert.areEqual(3, pages);
    }

    @IsTest
    static void summaryCountsOrders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Map<String, Object> s = OrderExplorerController.getSummary(a.Id);
        Assert.areEqual(120, (Integer) s.get('orders'));
        Assert.areEqual(0, (Integer) s.get('overdue'));
    }
}
