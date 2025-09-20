trigger MietvertragTrigger on Mietvertrag__c (before insert, before update, after insert, after update) {
    MietvertragTriggerHandler handler = new MietvertragTriggerHandler();
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