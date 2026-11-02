/**
 * Level 6. Scores every synced account in chunks, so it scales from 50 accounts to millions.
 *   Database.executeBatch(new AccountHealthBatch(), 200);
 *
 * Large-data-volume habits shown here:
 *  - QueryLocator start(): up to 50 million records, fetched by the platform in chunks
 *  - Selective filter on an indexed field (Warehouse_Id__c is an external ID, so it is indexed)
 *  - One aggregate query per chunk for metrics, never per account
 *  - Only changed accounts are updated (fewer DML rows, less sharing recalculation)
 *  - Database.Stateful to total the run across chunks; one log row at the end
 */
public with sharing class AccountHealthBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Integer scanned = 0;
    private Integer changed = 0;
    private final List<String> errors = new List<String>();
    private final Long started = System.currentTimeMillis();
    @TestVisible private Date today = Date.today();

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, Last_Order_Date__c, Open_Cases__c, Health_Score__c, Health_Status__c
            FROM Account
            WHERE Warehouse_Id__c != null
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<Account> scope) {
        scanned += scope.size();
        Map<Id, Decimal[]> windows = AccountHealthService.revenueWindows(new Map<Id, Account>(scope).keySet(), today);
        List<Account> updates = new List<Account>();
        for (Account a : scope) {
            Decimal[] w = windows.get(a.Id);
            AccountHealthService.Result r = AccountHealthService.score(a.Last_Order_Date__c, w[0], w[1], a.Open_Cases__c, today);
            if (a.Health_Score__c != r.score || a.Health_Status__c != r.status) {
                updates.add(new Account(Id = a.Id, Health_Score__c = r.score, Health_Status__c = r.status));
            }
        }
        for (Database.SaveResult sr : Database.update(updates, false)) {
            if (sr.isSuccess()) {
                changed++;
            } else {
                errors.add(sr.getId() + ': ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext ctx) {
        // Records_Processed__c = accounts scanned; Message__c lists any failed updates
        IntegrationLogger.log('AccountHealthBatch', 'SCORE', scanned, errors, null, started);
    }
}
