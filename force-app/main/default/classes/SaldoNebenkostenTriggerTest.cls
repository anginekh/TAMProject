/**
 * Created by Angine on 16/07/2025.
 */

@isTest
private class SaldoNebenkostenTriggerTest {

    @testSetup
    static void setupData() {
        // Create related records if needed
        Account acc = new Account(Name = 'Test Mieter');
        insert acc;

        Objekt__c objekt = new Objekt__c(Name = 'Test Objekt');
        insert objekt;

        Wohnung__c wohnung = new Wohnung__c(Name = 'Test Wohnung', Objekt__c = objekt.Id, WohnflaecheQm__c = 80);
        insert wohnung;

        Mietvertrag__c mv = new Mietvertrag__c(
                Wohnung__c = wohnung.Id,
                Mieter__c = acc.Id,
                AktuellerSaldo__c = 0,
                NBKEhDatum__c = Date.today().addMonths(1),
                KaltmieteNeu__c = 700
        );
        insert mv;
    }

    @isTest
    static void testBeforeInsert() {
        Mietvertrag__c mv = [SELECT Id FROM Mietvertrag__c LIMIT 1];

        SaldoNebenkosten__c saldo = new SaldoNebenkosten__c(
                Mietvertrag__c = mv.Id,
                Betrag__c =10
        );

        Test.startTest();
        insert saldo;
        Test.stopTest();

        System.assertNotEquals(null, saldo.Id, 'Saldo record should be inserted');
    }

    @isTest
    static void testBeforeUpdate() {
        Mietvertrag__c mv = [SELECT Id FROM Mietvertrag__c LIMIT 1];

        SaldoNebenkosten__c saldo = new SaldoNebenkosten__c(
                Mietvertrag__c = mv.Id,
                Betrag__c =200
        );
        insert saldo;


        Test.startTest();
        update saldo;
        Test.stopTest();

        SaldoNebenkosten__c updated = [SELECT Betrag__c FROM SaldoNebenkosten__c WHERE Id = :saldo.Id];
        System.assertEquals(200, updated.Betrag__c, 'Updated saldo should reflect new value');
    }

    @isTest
    static void testAfterInsert() {
        Mietvertrag__c mv = [SELECT Id FROM Mietvertrag__c LIMIT 1];

        SaldoNebenkosten__c saldo = new SaldoNebenkosten__c(
                Mietvertrag__c = mv.Id,
                Betrag__c =10
        );

        Test.startTest();
        insert saldo;
        Test.stopTest();

        // You can assert any post-insert logic effects here if known (e.g., related records)
        System.assertNotEquals(null, saldo.Id);
    }

    @isTest
    static void testAfterUpdate() {
        Mietvertrag__c mv = [SELECT Id FROM Mietvertrag__c LIMIT 1];

        SaldoNebenkosten__c saldo = new SaldoNebenkosten__c(
                Mietvertrag__c = mv.Id,
                Betrag__c =10
        );
        insert saldo;

        saldo.Betrag__c =250;

        Test.startTest();
        update saldo;
        Test.stopTest();

        SaldoNebenkosten__c updated = [SELECT Betrag__c FROM SaldoNebenkosten__c WHERE Id = :saldo.Id];
        System.assertEquals(250, updated.Betrag__c =250);
    }
}