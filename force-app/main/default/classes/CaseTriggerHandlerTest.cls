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
    static void testBeforeUpdateLogic_StatusOffenDeletesDate() {
        // Fetch the setup case that has NO date and set one to trigger delete logic
        Case c = [SELECT Id, DatumWiedervorlage__c
        FROM Case WHERE DatumWiedervorlage__c = null LIMIT 1];

        c.DatumWiedervorlage__c = Date.today().addDays(3);
        c.Status = 'Offen'; // This should trigger deletion of the date

        Test.startTest();
        update c;
        Test.stopTest();
    }
}