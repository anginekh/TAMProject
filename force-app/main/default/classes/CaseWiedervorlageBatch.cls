/**
 * Created by Angine on 21/09/2025.
 */

global class CaseWiedervorlageBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
                SELECT Id, Status, DatumWiedervorlage__c
                FROM Case
                WHERE Status = 'Wiedervorlage'
                AND DatumWiedervorlage__c = :System.today()
        ]);
    }

    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Case> updates = new List<Case>();
        for (SObject sobj : scope) {
            Case c = (Case)sobj;
            if (c.Status != 'Offen') {
                updates.add(new Case(Id = c.Id, Status = 'Offen', DatumWiedervorlage__c = null ));
            }
        }
        if (!updates.isEmpty()) {
            try {
                update updates;
            } catch (DmlException e) {
                System.debug('Failed to update Cases: ' + e.getMessage());
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
        // optional post-processing
    }
}