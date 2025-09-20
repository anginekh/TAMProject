/**
 * Created by Angine on 06/07/2025.
 */

trigger SaldoNebenkostenTrigger on SaldoNebenkosten__c (before insert, after insert, before update, after update) {
    SaldoNebenkostenTriggerHandler handler = new SaldoNebenkostenTriggerHandler();
    if (Trigger.isBefore){
        if (Trigger.isInsert){
            handler.onBeforeInsert(Trigger.new);
        }else if (Trigger.isUpdate){
            handler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }else{
        if (Trigger.isInsert){
            handler.onAfterInsert(Trigger.new);
        }else if (Trigger.isUpdate){
            handler.onAfterUpdate(Trigger.new, Trigger.oldMap);

        }
    }
}