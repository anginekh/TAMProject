/**
 * Created by Angine on 30/08/2025.
 */

public without sharing class MietvertragTriggerHandler {
    public void onBeforeInsert(List<Mietvertrag__c> newList){

    }

    public void onBeforeUpdate(List<Mietvertrag__c> newList, Map<Id, Mietvertrag__c> oldMap){

    }

    public void onAfterInsert(List<Mietvertrag__c> newList){

    }

    public void onAfterUpdate(List<Mietvertrag__c> newList, Map<Id, Mietvertrag__c> oldMap){
        updateBetriebskostenAndHeizkostenAltAndNKEDatum(newList,oldMap);
    }

    private static void updateBetriebskostenAndHeizkostenAltAndNKEDatum(List<Mietvertrag__c> newList, Map<Id, Mietvertrag__c> oldMap){
        List<Mietvertrag__c> mvUpdates = new List<Mietvertrag__c>();
        for (Mietvertrag__c m:newList){
            if (m.BetriebskostenNeu__c != oldMap.get(m.Id).BetriebskostenNeu__c &&
                    m.HeizkostenNeu__c != oldMap.get(m.Id).HeizkostenNeu__c){
                Date today = System.today();
                Date newDate = today.addMonths(2);
                // reset day to 1
                newDate = Date.newInstance(newDate.year(), newDate.month(), 1);
                mvUpdates.add(new Mietvertrag__c(Id = m.Id,
                        BetriebskostenAlt__c = oldMap.get(m.Id).BetriebskostenNeu__c,
                        NBKEhDatum__c = newDate,
                        HeizkostenAlt__c = oldMap.get(m.Id).HeizkostenNeu__c
                ));
            }
            else{
                if (m.BetriebskostenNeu__c != oldMap.get(m.Id).BetriebskostenNeu__c){
                    Date today = System.today();
                    Date newDate = today.addMonths(2);
                    // reset day to 1
                    newDate = Date.newInstance(newDate.year(), newDate.month(), 1);
                    mvUpdates.add(new Mietvertrag__c(Id = m.Id,
                            BetriebskostenAlt__c = oldMap.get(m.Id).BetriebskostenNeu__c,
                            NBKEhDatum__c = newDate
                    ));
                }
                if (m.HeizkostenNeu__c != oldMap.get(m.Id).HeizkostenNeu__c){
                    Date today = System.today();
                    Date newDate = today.addMonths(2);
                    // reset day to 1
                    newDate = Date.newInstance(newDate.year(), newDate.month(), 1);
                    mvUpdates.add(new Mietvertrag__c(Id = m.Id,
                            HeizkostenAlt__c = oldMap.get(m.Id).HeizkostenNeu__c,
                            NBKEhDatum__c = newDate
                    ));
                }
            }

        }
        update mvUpdates;
    }

}