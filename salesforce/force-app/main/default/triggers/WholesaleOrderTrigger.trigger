// Level 3: one trigger per object, no logic here. Everything lives in the handler.
trigger WholesaleOrderTrigger on Wholesale_Order__c (before insert, before update) {
    WholesaleOrderTriggerHandler.handle(Trigger.operationType, Trigger.new, Trigger.oldMap);
}
