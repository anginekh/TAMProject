/**
 * Created by Angine on 06/07/2025.
 */

public with sharing class SaldoNebenkostenTriggerHandler {

    public void onBeforeInsert(List<SaldoNebenkosten__c> newList){

    }

    public void onBeforeUpdate(List<SaldoNebenkosten__c> newList, Map<Id, SaldoNebenkosten__c> oldMap){

    }

    public void onAfterInsert(List<SaldoNebenkosten__c> newList){
        calculateSaldoNebenkosten(newList);

    }

    public void onAfterUpdate(List<SaldoNebenkosten__c> newList, Map<Id, SaldoNebenkosten__c> oldMap){
        calculateSaldoNebenkosten(newList);
    }

    private static void calculateSaldoNebenkosten(List<SaldoNebenkosten__c> newList){
        Set<Id> mietvertragIds = new Set <Id> ();
        for (SaldoNebenkosten__c s: newList){
            mietvertragIds.add(s.Mietvertrag__c);
        }
        List<SaldoNebenkosten__c> allSaldos = [SELECT Id, Betrag__c, Mietvertrag__c FROM SaldoNebenkosten__c WHERE Mietvertrag__c IN: mietvertragIds];
        Map <Id, List<SaldoNebenkosten__c>> mietvertragIdSaldoMap = new Map <Id, List<SaldoNebenkosten__c>> ();
        for (SaldoNebenkosten__c s: allSaldos){
            if (mietvertragIdSaldoMap.get(s.Mietvertrag__c) == null){
                mietvertragIdSaldoMap.put(s.Mietvertrag__c, new List<SaldoNebenkosten__c> ());
            }
            mietvertragIdSaldoMap.get(s.Mietvertrag__c).add(s);
        }
        Map <Id, Mietvertrag__c> mietvertragMap = new Map <Id, Mietvertrag__c> ([SELECT Id, AktuellerSaldo__c FROM Mietvertrag__c WHERE Id IN :mietvertragIds]);
        for (Id m:mietvertragIdSaldoMap.keySet()){
            Decimal aktuellerSaldo = 0;
            for (SaldoNebenkosten__c s: mietvertragIdSaldoMap.get(m)){
                aktuellerSaldo += s.Betrag__c;
            }
            mietvertragMap.get(m).AktuellerSaldo__c = aktuellerSaldo;
        }

        update mietvertragMap.values();
        System.debug('im here '+ mietvertragMap.values());

    }

}