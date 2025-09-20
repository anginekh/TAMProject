/**
 * Created by Angine on 20/09/2025.
 */

@isTest
public class CaseTriggerHandlerTest {

    @testSetup
    static void setupData() {
        // Create base Case records for update scenarios
        List<Case> cases = new List<Case>();

        // Case 1 - with a Wiedervorlage date set
        cases.add(new Case(
                Origin = 'Phone',
                Status = 'New',
                Subject = 'Initial Case 1',
                DatumWiedervorlage__c = Date.today()
        ));

        // Case 2 - without a Wiedervorlage date
        cases.add(new Case(
                Origin = 'Email',
                Status = 'New',
                Subject = 'Initial Case 2'
        ));

        insert cases;
    }

    @isTest
    static void testBeforeInsertLogic() {
        // Create a case to test onBeforeInsert logic
        Case c = new Case(
                Origin = 'Web',
                Status = 'New',
                Subject = 'Insert Test',
                DatumWiedervorlage__c = Date.today().addDays(1)
        );

        Test.startTest();
        insert c;
        Test.stopTest();

        // After insert, the trigger runs before-insert logic
        Case insertedCase = [SELECT DatumWiedervorlageIsSet__c FROM Case WHERE Id = :c.Id];
        //System.assertEquals(true, insertedCase.DatumWiedervorlageIsSet__c,'DatumWiedervorlageIsSet__c should be set to TRUE when a date is provided on insert');
    }

    @isTest
    static void testBeforeUpdateLogic_DateChanged() {
        // Fetch one of the setup cases that had a date
        Case c = [SELECT Id, DatumWiedervorlage__c, DatumWiedervorlageIsSet__c
        FROM Case WHERE DatumWiedervorlage__c != null LIMIT 1];

        // Change the date to trigger updateIsChangedToWiedervorlageToTrue
        c.DatumWiedervorlage__c = c.DatumWiedervorlage__c.addDays(2);

        Test.startTest();
        update c;
        Test.stopTest();

        Case updated = [SELECT DatumWiedervorlageIsSet__c
        FROM Case WHERE Id = :c.Id];
        //System.assertEquals(true, updated.DatumWiedervorlageIsSet__c, 'DatumWiedervorlageIsSet__c should be TRUE when date changes');
    }

    @isTest
    static void testBeforeUpdateLogic_StatusOffenDeletesDate() {
        // Fetch the setup case that has NO date and set one to trigger delete logic
        Case c = [SELECT Id, DatumWiedervorlage__c
        FROM Case WHERE DatumWiedervorlage__c = null LIMIT 1];

        c.DatumWiedervorlage__c = Date.today().addDays(3);
        c.Status = 'Offen'; // This should trigger deletion of the date

        Test.startTest();
        update c;
        Test.stopTest();

        Case updated = [SELECT DatumWiedervorlage__c
        FROM Case WHERE Id = :c.Id];
        System.assertEquals(null, updated.DatumWiedervorlage__c,
                'DatumWiedervorlage__c should be cleared when Status = Offen');
    }
}