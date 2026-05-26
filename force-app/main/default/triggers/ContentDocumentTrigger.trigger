/**
 * Created by Angine on 14/05/2026.
 */

trigger ContentDocumentTrigger on ContentDocument (after insert) {

    Set<Id> docIds = new Set<Id>();

    for(ContentDocument cd : Trigger.new) {
        docIds.add(cd.Id);
    }

    if(!docIds.isEmpty()) {
        System.enqueueJob(
                new VMT_DropboxUploadQueueable(docIds)
        );
    }
}