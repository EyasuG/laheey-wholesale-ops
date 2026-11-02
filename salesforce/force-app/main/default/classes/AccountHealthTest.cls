@IsTest
private class AccountHealthTest {

    @IsTest
    static void scoresTheThreeBands() {
        Date today = Date.newInstance(2026, 10, 28);
        AccountHealthService.Result healthy = AccountHealthService.score(today.addDays(-3), 3000, 2800, 0, today);
        Assert.areEqual(100, healthy.score);
        Assert.areEqual('Healthy', healthy.status);

        AccountHealthService.Result watch = AccountHealthService.score(today.addDays(-45), 2000, 2400, 3, today);
        Assert.areEqual(15 + 25 + 5, watch.score);
        Assert.areEqual('Watch', watch.status);

        AccountHealthService.Result risk = AccountHealthService.score(today.addDays(-120), 500, 3000, 7, today);
        Assert.areEqual(0, risk.score);
        Assert.areEqual('At Risk', risk.status);
        Assert.areEqual(3, risk.reasons.size(), 'Recency, trend and cases each explain the score');

        AccountHealthService.Result none = AccountHealthService.score(null, 0, 0, null, today);
        Assert.areEqual('At Risk', none.status);
    }

    @IsTest
    static void batchScoresEveryAccountInChunks() {
        List<Account> accts = TestDataFactory.accounts(3);
        TestDataFactory.metrics(accts[0].Id, 3000, 3000);   // steady  -> Healthy
        TestDataFactory.metrics(accts[1].Id, 500, 3000);    // falling -> lower
        update new Account(Id = accts[2].Id, Last_Order_Date__c = Date.today().addDays(-200), Open_Cases__c = 9);

        Test.startTest();
        Database.executeBatch(new AccountHealthBatch(), 200);
        Test.stopTest();

        Map<Id, Account> byId = new Map<Id, Account>([SELECT Health_Score__c, Health_Status__c FROM Account]);
        Assert.areEqual('Healthy', byId.get(accts[0].Id).Health_Status__c);
        Assert.isTrue(byId.get(accts[1].Id).Health_Score__c < byId.get(accts[0].Id).Health_Score__c);
        Assert.areEqual('At Risk', byId.get(accts[2].Id).Health_Status__c);
        Integration_Log__c log = [SELECT Job__c, Records_Processed__c, Status__c FROM Integration_Log__c];
        Assert.areEqual('AccountHealthBatch', log.Job__c);
        Assert.areEqual(3, log.Records_Processed__c);
        Assert.areEqual('Success', log.Status__c);
    }
}
