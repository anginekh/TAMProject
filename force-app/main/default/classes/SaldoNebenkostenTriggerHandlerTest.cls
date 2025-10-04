/**
 * Created by Angine on 07/07/2025.
 */

@isTest
private class SaldoNebenkostenTriggerHandlerTest {

    @isTest
    static void testCalculateSaldoOnInsertAndUpdate() {

        // create test objekt
        Objekt__c o = new Objekt__c(Name = 'Test Objekt', Gesamtwohnflaeche__c = 500);
        insert o;

        // create test Wohnung
        Wohnung__c w = new Wohnung__c(Name = 'Tets Wohnung', WohnflaecheQm__c = 50, Objekt__c = o.Id );
        Insert w;

        // Step 1: Create an Account
        Account a = new Account (Name = 'test Mieter');
        Insert a;

        // Step 1: Create a Mietvertrag__c
        Mietvertrag__c mietvertrag = new Mietvertrag__c(KaltmieteNeu__c = 500, Mieter__c = a.Id, Wohnung__c = w.Id);
        insert mietvertrag;

        // Step 2: Create initial saldo records
        SaldoNebenkosten__c saldo1 = new SaldoNebenkosten__c(
                Betrag__c = 100,
                Mietvertrag__c = mietvertrag.Id
        );
        SaldoNebenkosten__c saldo2 = new SaldoNebenkosten__c(
                Betrag__c = 200,
                Mietvertrag__c = mietvertrag.Id
        );

        List<SaldoNebenkosten__c> saldoList = new List<SaldoNebenkosten__c>{saldo1, saldo2};
        insert saldoList;

        // Step 3: Call the trigger handler's onAfterInsert
        Test.startTest();
        new SaldoNebenkostenTriggerHandler().onAfterInsert(saldoList);
        Test.stopTest();

        // Step 4: Reload the Mietvertrag and assert saldo was updated
        Mietvertrag__c updatedMietvertrag = [
                SELECT Id, AktuellerSaldo__c
                FROM Mietvertrag__c
                WHERE Id = :mietvertrag.Id
        ];

        System.assertEquals(300, updatedMietvertrag.AktuellerSaldo__c, 'AktuellerSaldo__c should be sum of 100 + 200');

        // Step 5: Update one saldo to change the amount
        saldo1.Betrag__c = 150;
        update saldo1;

        // Step 6: Call the trigger handler's onAfterUpdate
        new SaldoNebenkostenTriggerHandler().onAfterUpdate(
                new List<SaldoNebenkosten__c>{saldo1},
                new Map<Id, SaldoNebenkosten__c>{saldo1.Id => saldo1}
        );

        // Step 7: Verify updated saldo
        updatedMietvertrag = [
                SELECT Id, AktuellerSaldo__c
                FROM Mietvertrag__c
                WHERE Id = :mietvertrag.Id
        ];

        System.assertEquals(350, updatedMietvertrag.AktuellerSaldo__c, 'AktuellerSaldo__c should be 150 + 200');
    }
}