@IsTest
private class WarehouseSyncJobTest {

    @IsTest
    static void accountsPageUpsertsAndLogsTheBadRow() {
        WarehouseHttpMock mock = new WarehouseHttpMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        System.enqueueJob(new WarehouseSyncJob());
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Account WHERE Warehouse_Id__c LIKE 'ACC-000000%'], 'Two valid accounts land');
        Account a = [SELECT Name, Tier__c, Lifetime_Revenue__c, Last_Synced__c FROM Account WHERE Warehouse_Id__c = 'ACC-0000001'];
        Assert.areEqual('Platinum', a.Tier__c);
        Assert.areEqual(120000.50, a.Lifetime_Revenue__c);
        Assert.isNotNull(a.Last_Synced__c);

        Integration_Log__c log = [SELECT Status__c, Records_Processed__c, Errors__c, Cursor__c FROM Integration_Log__c];
        Assert.areEqual('Partial', log.Status__c, 'The restricted-picklist row fails without failing the page');
        Assert.areEqual(3, log.Records_Processed__c);
        Assert.areEqual(1, log.Errors__c);
        Assert.areEqual('3', log.Cursor__c);
    }

    @IsTest
    static void rerunningAPageIsIdempotent() {
        Test.setMock(HttpCalloutMock.class, new WarehouseHttpMock());
        Test.startTest();
        System.enqueueJob(new WarehouseSyncJob());
        System.enqueueJob(new WarehouseSyncJob());
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Warehouse_Id__c = 'ACC-0000001'], 'Upsert on the external ID never duplicates');
    }

    @IsTest
    static void contactsOrdersAndMetricsAttachToParentsByExternalId() {
        insert new Account(Name = 'Blue Door Cafe', Warehouse_Id__c = 'ACC-0000001');
        Test.setMock(HttpCalloutMock.class, new WarehouseHttpMock());
        WarehouseSyncJob.Settings cfg = new WarehouseSyncJob.Settings();
        Test.startTest();
        System.enqueueJob(new WarehouseSyncJob(WarehouseSyncJob.SyncStage.CONTACTS, '0', cfg));
        System.enqueueJob(new WarehouseSyncJob(WarehouseSyncJob.SyncStage.ORDERS, '0', cfg));
        System.enqueueJob(new WarehouseSyncJob(WarehouseSyncJob.SyncStage.METRICS, '0', cfg));
        Test.stopTest();

        Id accountId = [SELECT Id FROM Account WHERE Warehouse_Id__c = 'ACC-0000001'].Id;
        Assert.areEqual(accountId, [SELECT AccountId FROM Contact WHERE Warehouse_Id__c = 'CON-0000001'].AccountId);
        Assert.areEqual(2, [SELECT COUNT() FROM Wholesale_Order__c WHERE Account__c = :accountId]);
        Assert.areEqual(280, [SELECT Total__c FROM Wholesale_Order__c WHERE Name = 'LWO-00000001'].Total__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Account_Metric__c WHERE Account__c = :accountId]);
        Assert.areEqual(3, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Success']);
    }

    @IsTest
    static void anOutageIsLoggedAndStopsTheChain() {
        WarehouseHttpMock mock = new WarehouseHttpMock();
        mock.forceStatus = 500;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        System.enqueueJob(new WarehouseSyncJob());
        Test.stopTest();
        Integration_Log__c log = [SELECT Status__c, Message__c FROM Integration_Log__c];
        Assert.areEqual('Failed', log.Status__c);
        Assert.isTrue(log.Message__c.contains('HTTP 500'), log.Message__c);
    }

    @IsTest
    static void schedulerEnqueuesTheSync() {
        Test.setMock(HttpCalloutMock.class, new WarehouseHttpMock());
        Test.startTest();
        String jobId = System.schedule('Test warehouse sync', '0 0 2 * * ?', new WarehouseSyncScheduler());
        Test.stopTest();
        Assert.isNotNull(jobId);
    }
}
