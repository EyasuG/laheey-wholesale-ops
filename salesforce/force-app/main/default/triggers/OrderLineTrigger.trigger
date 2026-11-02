// Level 3: keeps the parent order's Subtotal and Line Count in step with its lines.
trigger OrderLineTrigger on Order_Line__c (after insert, after update, after delete, after undelete) {
    OrderLineRollup.recalculate(Trigger.isDelete ? Trigger.old : Trigger.new, Trigger.oldMap);
}
