/**
 * Created by Angine on 21/09/2025.
 */

@isTest
private class CaseWiedervorlageBatchTest {
    @isTest static void testBatchChangesStatus() {
        Case c = new Case(
                Status = 'Wiedervorlage',
                DatumWiedervorlage__c = System.today()
                // add other required Case fields here, e.g. Origin
        );
        insert c;

        Test.startTest();
        Database.executeBatch(new CaseWiedervorlageBatch(), 200);
        Test.stopTest();

        c = [SELECT Status, DatumWiedervorlage__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Offen', c.Status);
        System.assertEquals(null, c.DatumWiedervorlage__c);
    }
}