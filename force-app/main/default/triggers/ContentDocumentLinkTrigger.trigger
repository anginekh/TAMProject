/**
 * Created by Angine on 26/10/2026.
 */

trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    if (ContentDocumentLinkTriggerControl.skipDropboxAutomation) {
        return;
    }
    Set<Id> docIds = new Set<Id>();

    for (ContentDocumentLink cdl : Trigger.new) {
        if (cdl.ContentDocumentId != null) {
            docIds.add(cdl.ContentDocumentId);
        }
    }

    if (!docIds.isEmpty()) {
        System.enqueueJob(
                new VMT_DropboxUploadQueueable(docIds)
        );
    }
}