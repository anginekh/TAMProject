trigger CaseTrigger on Case (before insert, before update, after insert, after update) {

CaseTriggerHandler handler = new CaseTriggerHandler ();
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