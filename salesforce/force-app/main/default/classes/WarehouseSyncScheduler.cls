/**
 * Level 4. Runs the warehouse sync every night.
 *   System.schedule('Laheey nightly warehouse sync', '0 0 2 * * ?', new WarehouseSyncScheduler());
 */
public with sharing class WarehouseSyncScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        System.enqueueJob(new WarehouseSyncJob());
    }
}
