/**
 * Created by Angine on 02/10/2025.
 */

@isTest
public class NK_UpdateNKAndSaldoOnMietvertragTest {

    @testSetup
    static void setupData() {
        // Create a test account (Mieter)
        Account mieter = new Account(Name = 'Test Mieter');
        insert mieter;

        // Create Objekt (assuming lookup for NK + Mietzahlung, adapt if different object model)
        Objekt__c objekt = new Objekt__c(Name = 'Objekt 1', Gesamtwohnflaeche__c = 600);
        insert objekt;

        // Create Wohnung
        Wohnung__c wohnung = new Wohnung__c(Name = 'Objekt 1', WohnflaecheQm__c = 60, Objekt__c = objekt.Id);
        insert wohnung;

        // Create Mietvertrag
        Mietvertrag__c mv = new Mietvertrag__c(
                Mieter__c = mieter.Id,
                BetriebskostenNeu__c = 100,
                HeizkostenNeu__c = 50,
                Eingezogen__c = Date.newInstance(2024, 1, 15),
                Ausgezogen__c = null,
                KaltmieteNeu__c = 600,
                Wohnung__c = wohnung.Id
        );
        insert mv;

        // Create Nebenkosten
        Nebenkosten__c nk = new Nebenkosten__c(
                Objekt__c = objekt.Id,
                Jahr__c = '2024',
                Allgemeinstrom__c = 20000,
                NebenkostenabrechnungDurchgefuehrt__c = false
        );
        insert nk;

        // Create Mietzahlung
        Mietzahlung__c mz = new Mietzahlung__c(
                Mietvertrag__c = mv.Id,
                Mieter__c = mieter.Id,
                Objekt__c = objekt.Id,
                Jahr__c = '2024',
                NebenkostenBezahlt2024__c = 50
        );
        insert mz;

        // Create Heizkosten
        Heizkosten__c hk = new Heizkosten__c(
                Objekt__c = objekt.Id,
                Jahr__c = '2024',
                Mietvertrag__c = mv.Id,
                AnteilHKVerbrauch__c = 500,
                AnteilHKWohnflaeche__c = 500

        );
        insert hk;

        // Create Gebuehr
        Gebuehr__c g = new Gebuehr__c(
                Account__c = mieter.Id,
                Zahlungsstatus__c = 'Offen',
                Betrag__c = 100
        );
        insert g;
    }


    @isTest
    static void testNkUpdateNkAndSaldo() {
        // Fetch Nebenkosten
        Nebenkosten__c nk = [SELECT Id FROM Nebenkosten__c LIMIT 1];

        RecordType rt = [SELECT Id FROM RecordType WHERE Name = 'KEYVALUE' LIMIT 1];
        cadmus_core__Data_Source__c ds1 = new cadmus_core__Data_Source__c (Name = 'inputMap', RecordTypeId = rt.Id);
        insert ds1;

        // Call the invocable method
        Test.startTest();
        NK_UpdateNKAndSaldoOnMietvertrag.nk_UpdateNkAndSaldo(new List<String>{ nk.Id });
        Test.stopTest();

        // Validate Nebenkosten updated
        nk = [SELECT Id, NebenkostenabrechnungDurchgefuehrt__c FROM Nebenkosten__c WHERE Id = :nk.Id];
        System.assertEquals(true, nk.NebenkostenabrechnungDurchgefuehrt__c, 'Nebenkosten should be marked as processed');

        // Validate Mietvertrag updated
        Mietvertrag__c mv = [SELECT Id, BetriebskostenNeu__c, HeizkostenNeu__c FROM Mietvertrag__c LIMIT 1];
        System.assertNotEquals(100, mv.BetriebskostenNeu__c, 'Betriebskosten should be recalculated');
        System.assertNotEquals(50, mv.HeizkostenNeu__c, 'Heizkosten should be recalculated');

        // Validate Saldo inserted
        List<SaldoNebenkosten__c> saldoList = [SELECT Id, Betrag__c, Jahr__c FROM SaldoNebenkosten__c];
        System.assert(!saldoList.isEmpty(), 'Saldo should be inserted');
        System.assertEquals('2024', saldoList[0].Jahr__c);

        // Validate Gebuehr updated
        List<Gebuehr__c> gebuehren = [SELECT Id, Zahlungsstatus__c FROM Gebuehr__c];
        System.assertEquals('Berechnet in NK-Saldo', gebuehren[0].Zahlungsstatus__c, 'Gebuehr should be updated');
    }
}
