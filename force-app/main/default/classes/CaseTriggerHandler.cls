/**
 * Created by Angine on 20/09/2025.
 */

public with sharing class CaseTriggerHandler {

    public void onBeforeInsert(List<Case> newList){

    }

    public void onBeforeUpdate(List<Case> newList, Map<Id, Case> oldMap){
        deleteDatumWiedervorlage(newList, oldMap);

    }

    public void onAfterInsert(List<Case> newList){

    }

    public void onAfterUpdate(List<Case> newList, Map<Id, Case> oldMap){

    }

    /*---------------------********************+******************---------------------*/

    private static void deleteDatumWiedervorlage(List<Case> newList, Map<Id, Case> oldMap){
        for (Case c:newList) {
            if (c.DatumWiedervorlage__c != null && c.Status == 'Offen') {
                c.DatumWiedervorlage__c = null;

            }
        }
    }

}