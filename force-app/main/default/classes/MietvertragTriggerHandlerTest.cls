/**
 * Created by Angine on 30/08/2025.
 */

@isTest
public class MietvertragTriggerHandlerTest {

    @testSetup
    static void setupData() {

        // create test objekt
        Objekt__c o = new Objekt__c(Name = 'Test Objekt', Gesamtwohnflaeche__c = 500);
        insert o;

        // create test Wohnung
        Wohnung__c w = new Wohnung__c(Name = 'Tets Wohnung', WohnflaecheQm__c = 50, Objekt__c = o.Id );
        Insert w;
        // Create Mietvertrag records for testing
        List<Mietvertrag__c> mvs = new List<Mietvertrag__c>();
        Account acc = new Account(Name = 'Test Mieter');
        insert acc;
        for (Integer i = 0; i < 3; i++) {
            mvs.add(new Mietvertrag__c(
                    BetriebskostenNeu__c = 100,
                    HeizkostenNeu__c = 50,
                    KaltmieteNeu__c = 300,
                    Mieter__c = acc.Id,
                    Wohnung__c = w.Id

            ));
        }
        insert mvs;
    }

    @isTest
    static void testUpdateBothBetriebUndHeizkosten() {
        List<Mietvertrag__c> mvs = [SELECT Id, BetriebskostenNeu__c, HeizkostenNeu__c,
                BetriebskostenAlt__c, HeizkostenAlt__c, NBKEhDatum__c
        FROM Mietvertrag__c];

        Test.startTest();
        for (Mietvertrag__c mv : mvs) {
            mv.BetriebskostenNeu__c = mv.BetriebskostenNeu__c + 10;
            mv.HeizkostenNeu__c = mv.HeizkostenNeu__c + 5;
        }
        update mvs;
        Test.stopTest();

        List<Mietvertrag__c> updatedMvs = [SELECT Id, BetriebskostenNeu__c, HeizkostenNeu__c,
                BetriebskostenAlt__c, HeizkostenAlt__c, NBKEhDatum__c
        FROM Mietvertrag__c];
        Date expectedDate = Date.today().addMonths(2);
        expectedDate = Date.newInstance(expectedDate.year(), expectedDate.month(), 1);

        for (Mietvertrag__c mv : updatedMvs) {
            System.assertEquals(100, mv.BetriebskostenAlt__c, 'BetriebskostenAlt should copy old Neu');
            System.assertEquals(50, mv.HeizkostenAlt__c, 'HeizkostenAlt should copy old Neu');
            System.assertEquals(expectedDate, mv.NBKEhDatum__c, 'NBKEhDatum should be set correctly');
        }
    }

    @isTest
    static void testUpdateOnlyBetriebskosten() {
        Mietvertrag__c mv = [SELECT Id, BetriebskostenNeu__c, HeizkostenNeu__c FROM Mietvertrag__c LIMIT 1];

        Test.startTest();
        mv.BetriebskostenNeu__c = mv.BetriebskostenNeu__c + 20;
        update mv;
        Test.stopTest();

        Mietvertrag__c updated = [SELECT BetriebskostenAlt__c, NBKEhDatum__c, HeizkostenAlt__c
        FROM Mietvertrag__c WHERE Id = :mv.Id];
        Date expectedDate = Date.today().addMonths(2);
        expectedDate = Date.newInstance(expectedDate.year(), expectedDate.month(), 1);

        System.assertEquals(100, updated.BetriebskostenAlt__c, 'BetriebskostenAlt should be updated');
        System.assertEquals(expectedDate, updated.NBKEhDatum__c, 'NBKEhDatum should be updated');
        System.assertEquals(0, updated.HeizkostenAlt__c, 'HeizkostenAlt should not change');
    }

    @isTest
    static void testUpdateOnlyHeizkosten() {
        Mietvertrag__c mv = [SELECT Id, BetriebskostenNeu__c, HeizkostenNeu__c FROM Mietvertrag__c LIMIT 1 OFFSET 1];

        Test.startTest();
        mv.HeizkostenNeu__c = mv.HeizkostenNeu__c + 15;
        update mv;
        Test.stopTest();

        Mietvertrag__c updated = [SELECT BetriebskostenAlt__c, HeizkostenAlt__c, NBKEhDatum__c
        FROM Mietvertrag__c WHERE Id = :mv.Id];
        Date expectedDate = Date.today().addMonths(2);
        expectedDate = Date.newInstance(expectedDate.year(), expectedDate.month(), 1);

        System.assertEquals(0, updated.BetriebskostenAlt__c, 'BetriebskostenAlt should not change');
        System.assertEquals(50, updated.HeizkostenAlt__c, 'HeizkostenAlt should be updated');
        System.assertEquals(expectedDate, updated.NBKEhDatum__c, 'NBKEhDatum should be updated');
    }

    @isTest
    static void testNoChange() {
        Mietvertrag__c mv = [SELECT Id, BetriebskostenNeu__c, HeizkostenNeu__c FROM Mietvertrag__c LIMIT 1 OFFSET 2];

        Test.startTest();
        update mv; // no field changes
        Test.stopTest();

        Mietvertrag__c updated = [SELECT BetriebskostenAlt__c, HeizkostenAlt__c, NBKEhDatum__c
        FROM Mietvertrag__c WHERE Id = :mv.Id];

        System.assertEquals(0, updated.BetriebskostenAlt__c, 'Should not change when no difference');
        System.assertEquals(0, updated.HeizkostenAlt__c, 'Should not change when no difference');
        System.assertEquals(null, updated.NBKEhDatum__c, 'Should not change when no difference');
    }
}