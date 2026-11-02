@IsTest
private class AgentActionsTest {

    @IsTest
    static void orderStatusFromSalesforceThenWarehouseThenNotFound() {
        Account a = TestDataFactory.accounts(1)[0];
        Wholesale_Order__c o = TestDataFactory.orders(a.Id, 1, 'Roasting')[0];
        Test.setMock(HttpCalloutMock.class, new WarehouseHttpMock());

        List<OrderStatusAction.Request> reqs = new List<OrderStatusAction.Request>();
        for (String num : new List<String>{ o.Name.toLowerCase(), 'LWO-00000777', 'LWO-99999999', '' }) {
            OrderStatusAction.Request r = new OrderStatusAction.Request();
            r.orderNumber = num;
            reqs.add(r);
        }
        Test.startTest();
        List<OrderStatusAction.Result> res = OrderStatusAction.getStatus(reqs);
        Test.stopTest();

        Assert.isTrue(res[0].found, 'Synced order found in Salesforce, case-insensitively');
        Assert.areEqual('Roasting', res[0].status);
        Assert.isTrue(res[1].found, 'Older order fetched live from the warehouse');
        Assert.areEqual('Shipped', res[1].status);
        Assert.isTrue(res[1].summary.contains('shipped'), res[1].summary);
        Assert.isFalse(res[2].found);
        Assert.isTrue(res[2].summary.contains('couldn\'t find'), res[2].summary);
        Assert.isFalse(res[3].found);
    }

    @IsTest
    static void orderStatusSurvivesAnOutage() {
        WarehouseHttpMock mock = new WarehouseHttpMock();
        mock.forceStatus = 503;
        Test.setMock(HttpCalloutMock.class, mock);
        OrderStatusAction.Request r = new OrderStatusAction.Request();
        r.orderNumber = 'LWO-00000123';
        OrderStatusAction.Result res = OrderStatusAction.getStatus(new List<OrderStatusAction.Request>{ r })[0];
        Assert.isFalse(res.found);
        Assert.isTrue(res.summary.contains('try again'), res.summary);
    }

    @IsTest
    static void accountInsightsMatchTheHealthService() {
        List<Account> accts = TestDataFactory.accounts(2);
        TestDataFactory.metrics(accts[0].Id, 3000, 3000);
        update new Account(Id = accts[1].Id, Last_Order_Date__c = Date.today().addDays(-150), Open_Cases__c = 8);

        List<AccountInsightAction.Request> reqs = new List<AccountInsightAction.Request>();
        for (Account a : accts) {
            AccountInsightAction.Request r = new AccountInsightAction.Request();
            r.accountId = a.Id;
            reqs.add(r);
        }
        List<AccountInsightAction.Result> res = AccountInsightAction.getInsights(reqs);
        Assert.areEqual('Healthy', res[0].healthStatus);
        Assert.isTrue(res[0].summary.contains('Test Cafe 0'), res[0].summary);
        Assert.areEqual('At Risk', res[1].healthStatus);
        Assert.isTrue(res[1].summary.contains('call this week'), res[1].summary);
    }
}
