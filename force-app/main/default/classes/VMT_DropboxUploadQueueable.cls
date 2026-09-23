/**
 * Created by Angine on 14/05/2026.
 */

public with sharing class VMT_DropboxUploadQueueable
        implements Queueable, Database.AllowsCallouts {

    private Set<Id> contentDocumentIds;

    public VMT_DropboxUploadQueueable(Set<Id> contentDocumentIds) {
        this.contentDocumentIds = contentDocumentIds;
    }

    public void execute(QueueableContext context) {

        /*
         * -------------------------------------------------
         * Basic validation
         * -------------------------------------------------
         */

        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            System.debug('No ContentDocumentIds supplied.');
            return;
        }


        /*
         * -------------------------------------------------
         * STEP 1
         * Query latest ContentVersions
         * -------------------------------------------------
         */

        List<ContentVersion> versions = [
                SELECT Id,
                        Title,
                        FileExtension,
                        VersionData,
                        ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                AND IsLatest = TRUE
        ];


        if (versions.isEmpty()) {
            System.debug('No latest ContentVersions found.');
            return;
        }


        /*
         * -------------------------------------------------
         * STEP 2
         * Query ContentDocumentLinks
         * -------------------------------------------------
         */

        List<ContentDocumentLink> docLinks = [
                SELECT ContentDocumentId,
                        LinkedEntityId,
                        LinkedEntity.Type
                FROM ContentDocumentLink
                WHERE ContentDocumentId IN :contentDocumentIds
        ];


        System.debug(
                'STEP 2 - Original ContentDocumentLinks: ' + docLinks
        );


        /*
         * -------------------------------------------------
         * STEP 3
         * Filter User ContentDocumentLinks
         * -------------------------------------------------
         *
         * Salesforce User Ids start with 005.
         */

        List<ContentDocumentLink> filteredLinks =
                new List<ContentDocumentLink>();

        for (ContentDocumentLink cdl : docLinks) {

            if (cdl.LinkedEntityId == null) {
                continue;
            }

            if (String.valueOf(cdl.LinkedEntityId).startsWith('005')) {
                continue;
            }

            filteredLinks.add(cdl);
        }

        docLinks = filteredLinks;


        System.debug(
                'STEP 3 - Filtered ContentDocumentLinks: ' + docLinks
        );


        /*
         * -------------------------------------------------
         * STEP 4
         * Group ContentDocumentLinks by ContentDocument
         * -------------------------------------------------
         */

        Map<Id, List<ContentDocumentLink>> linksByDocument =
                new Map<Id, List<ContentDocumentLink>>();

        Set<Id> emailMessageIds = new Set<Id>();
        Set<Id> caseIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();


        for (ContentDocumentLink cdl : docLinks) {

            if (!linksByDocument.containsKey(cdl.ContentDocumentId)) {
                linksByDocument.put(
                        cdl.ContentDocumentId,
                        new List<ContentDocumentLink>()
                );
            }

            linksByDocument.get(cdl.ContentDocumentId).add(cdl);


            if (cdl.LinkedEntityId == null) {
                continue;
            }


            /*
             * EmailMessage
             */

            if (cdl.LinkedEntityId.getSObjectType() ==
                    EmailMessage.SObjectType) {

                emailMessageIds.add(cdl.LinkedEntityId);
            }


            /*
             * Direct Case
             */

            else if (cdl.LinkedEntityId.getSObjectType() ==
                    Case.SObjectType) {

                caseIds.add(cdl.LinkedEntityId);
            }


            /*
             * Direct Account / Mieter
             */

            else if (cdl.LinkedEntityId.getSObjectType() ==
                    Account.SObjectType) {

                accountIds.add(cdl.LinkedEntityId);
            }
        }


        /*
         * -------------------------------------------------
         * STEP 5
         * Query EmailMessages
         * -------------------------------------------------
         */

        Map<Id, EmailMessage> emailMap =
                new Map<Id, EmailMessage>();


        if (!emailMessageIds.isEmpty()) {

            emailMap = new Map<Id, EmailMessage>([
                    SELECT Id,
                            ParentId,
                            Parent.CaseNumber,
                            RelatedToId
                    FROM EmailMessage
                    WHERE Id IN :emailMessageIds
            ]);
        }


        /*
         * -------------------------------------------------
         * STEP 6
         * Query Cases
         * -------------------------------------------------
         */

        Map<Id, Case> caseMap =
                new Map<Id, Case>();


        if (!caseIds.isEmpty()) {

            caseMap = new Map<Id, Case>([
                    SELECT Id,
                            CaseNumber
                    FROM Case
                    WHERE Id IN :caseIds
            ]);
        }


        /*
         * -------------------------------------------------
         * STEP 7
         * Query Accounts / Mieter
         * -------------------------------------------------
         *
         * We query the Account so the Mieter relationship
         * is explicitly validated as an Account.
         */

        Map<Id, Account> accountMap =
                new Map<Id, Account>();


        if (!accountIds.isEmpty()) {

            accountMap = new Map<Id, Account>([
                    SELECT Id,
                            Name
                    FROM Account
                    WHERE Id IN :accountIds
            ]);
        }


        /*
         * -------------------------------------------------
         * STEP 8
         * Prepare FileLink records
         * -------------------------------------------------
         *
         * These two lists intentionally have identical
         * indexes:
         *
         * fileLinksToInsert[0]
         *     -> fileLinkDocumentIds[0]
         */

        List<FileLink__c> fileLinksToInsert =
                new List<FileLink__c>();

        List<Id> fileLinkDocumentIds =
                new List<Id>();


        /*
         * -------------------------------------------------
         * STEP 9
         * Track processing errors
         * -------------------------------------------------
         *
         * If ANY exception occurs while processing a
         * ContentDocument, that document must NOT be
         * deleted during this execution.
         */

        Set<Id> documentsWithProcessingErrors =
                new Set<Id>();


        Http http = new Http();


        /*
         * -------------------------------------------------
         * STEP 10
         * Process each ContentDocument
         * -------------------------------------------------
         */

        for (ContentVersion cv : versions) {

            Id documentId = cv.ContentDocumentId;


            try {

                /*
                 * ---------------------------------------------
                 * Get relevant ContentDocumentLinks
                 * ---------------------------------------------
                 */

                List<ContentDocumentLink> relatedLinks =
                        linksByDocument.get(documentId);


                if (relatedLinks == null ||
                        relatedLinks.isEmpty()) {

                    System.debug(
                            'No relevant ContentDocumentLinks for '
                                    + documentId
                                    + '. ContentDocument will remain.'
                    );

                    continue;
                }


                /*
                 * ---------------------------------------------
                 * Build original filename
                 * ---------------------------------------------
                 */

                String originalName = cv.Title;

                if (String.isBlank(originalName)) {
                    originalName = 'SalesforceFile';
                }


                String extension = '';

                if (String.isNotBlank(cv.FileExtension)) {
                    extension = '.' + cv.FileExtension;
                }


                originalName = originalName.replaceAll(
                        '[^a-zA-Z0-9._-]',
                        '_'
                );


                /*
                 * ---------------------------------------------
                 * Current DateTime
                 * ---------------------------------------------
                 */

                String datetimeString =
                        Datetime.now().format();


                /*
                 * ---------------------------------------------
                 * Determine filename relationship information
                 * ---------------------------------------------
                 *
                 * These values are only used for the Dropbox
                 * filename.
                 *
                 * FileLink relationships are determined
                 * independently for each CDL below.
                 */

                String filenameCaseNumber;
                String filenameMieterId;
                String filenameMietvertragId;


                for (ContentDocumentLink cdl : relatedLinks) {

                    if (cdl.LinkedEntityId == null) {
                        continue;
                    }


                    /*
                     * -----------------------------------------
                     * EmailMessage
                     * -----------------------------------------
                     */

                    if (cdl.LinkedEntityId.getSObjectType() ==
                            EmailMessage.SObjectType) {

                        EmailMessage em =
                                emailMap.get(cdl.LinkedEntityId);


                        if (em == null) {
                            continue;
                        }


                        /*
                         * Email -> Case
                         */

                        if (em.ParentId != null &&
                                filenameCaseNumber == null) {

                            filenameCaseNumber =
                                    em.Parent != null
                                            ? em.Parent.CaseNumber
                                            : null;
                        }


                        /*
                         * Email -> Mieter Account
                         */

                        if (em.RelatedToId != null &&
                                em.RelatedToId.getSObjectType() ==
                                        Account.SObjectType &&
                                filenameMieterId == null) {

                            filenameMieterId =
                                    String.valueOf(em.RelatedToId);
                        }
                    }


                    /*
                     * -----------------------------------------
                     * Direct Case
                     * -----------------------------------------
                     */

                    else if (
                            cdl.LinkedEntityId.getSObjectType() ==
                                    Case.SObjectType
                    ) {

                        Case linkedCase =
                                caseMap.get(cdl.LinkedEntityId);


                        if (linkedCase != null &&
                                filenameCaseNumber == null) {

                            filenameCaseNumber =
                                    linkedCase.CaseNumber;
                        }
                    }


                    /*
                     * -----------------------------------------
                     * Direct Account / Mieter
                     * -----------------------------------------
                     */

                    else if (
                            cdl.LinkedEntityId.getSObjectType() ==
                                    Account.SObjectType
                    ) {

                        /*
                         * We already queried the Account.
                         *
                         * The ID is sufficient for the current
                         * filename convention.
                         */

                        if (accountMap.containsKey(
                                cdl.LinkedEntityId
                        )
                                &&
                                filenameMieterId == null) {

                            filenameMieterId =
                                    String.valueOf(
                                            cdl.LinkedEntityId
                                    );
                        }
                    }


                    /*
                     * -----------------------------------------
                     * Mietvertrag
                     * -----------------------------------------
                     */

                    else if (
                            cdl.LinkedEntityId.getSObjectType() ==
                                    Mietvertrag__c.SObjectType
                    ) {

                        if (filenameMietvertragId == null) {

                            filenameMietvertragId =
                                    String.valueOf(
                                            cdl.LinkedEntityId
                                    );
                        }
                    }
                }


                /*
                 * Sanitize CaseNumber.
                 */

                if (String.isNotBlank(filenameCaseNumber)) {

                    filenameCaseNumber =
                            filenameCaseNumber.replaceAll(
                                    '[^a-zA-Z0-9_-]',
                                    '_'
                            );
                }


                /*
                 * ---------------------------------------------
                 * Build Dropbox filename
                 * ---------------------------------------------
                 */

                String fileName =
                        (String.isNotBlank(filenameCaseNumber)
                                ? 'Case:' + filenameCaseNumber + '_'
                                : '')
                                +
                                (String.isNotBlank(filenameMieterId)
                                        ? 'MieterId:' + filenameMieterId + '_'
                                        : '')
                                +
                                (String.isNotBlank(filenameMietvertragId)
                                        ? 'MVId:' + filenameMietvertragId + '_'
                                        : '')
                                +
                                datetimeString
                                + '_'
                                + originalName
                                + extension;


                /*
                 * ---------------------------------------------
                 * Dropbox path
                 * ---------------------------------------------
                 */

                String dropboxPath =
                        '/SalesforceFiles_AutomatedUpload/'
                                + fileName;


                /*
                 * ---------------------------------------------
                 * Get Dropbox access token
                 * ---------------------------------------------
                 */

                String token =
                        VMT_DropboxTokenService.getAccessToken();


                if (String.isBlank(token)) {

                    throw new CalloutException(
                            'Dropbox access token is blank.'
                    );
                }


                /*
                 * ---------------------------------------------
                 * Upload file to Dropbox
                 * ---------------------------------------------
                 */

                HttpRequest uploadReq =
                        new HttpRequest();

                uploadReq.setEndpoint(
                        'https://content.dropboxapi.com/2/files/upload'
                );

                uploadReq.setMethod('POST');

                uploadReq.setHeader(
                        'Authorization',
                        'Bearer ' + token
                );

                uploadReq.setHeader(
                        'Content-Type',
                        'application/octet-stream'
                );

                uploadReq.setHeader(
                        'Dropbox-API-Arg',
                        JSON.serialize(
                                new Map<String, Object>{
                                        'path' => dropboxPath,
                                        'mode' => 'add',
                                        'autorename' => true,
                                        'mute' => false
                                }
                        )
                );

                uploadReq.setBodyAsBlob(
                        cv.VersionData
                );


                HttpResponse uploadRes =
                        http.send(uploadReq);


                System.debug(
                        'Dropbox upload response for '
                                + documentId
                                + ': '
                                + uploadRes.getStatusCode()
                                + ' '
                                + uploadRes.getBody()
                );


                /*
                 * Upload failed.
                 */

                if (uploadRes.getStatusCode() < 200 ||
                        uploadRes.getStatusCode() >= 300) {

                    System.debug(
                            'Dropbox upload failed for '
                                    + documentId
                                    + ': '
                                    + uploadRes.getBody()
                    );

                    continue;
                }


                /*
                 * ---------------------------------------------
                 * Parse upload response
                 * ---------------------------------------------
                 */

                Map<String, Object> uploadResult =
                        (Map<String, Object>)
                                JSON.deserializeUntyped(
                                        uploadRes.getBody()
                                );


                String uploadedPath =
                        (String) uploadResult.get(
                                'path_lower'
                        );


                if (String.isBlank(uploadedPath)) {

                    System.debug(
                            'Dropbox upload returned no path for '
                                    + documentId
                    );

                    continue;
                }


                /*
                 * ---------------------------------------------
                 * Create shared link
                 * ---------------------------------------------
                 */

                String shareToken =
                        VMT_DropboxTokenService.getAccessToken();


                if (String.isBlank(shareToken)) {

                    throw new CalloutException(
                            'Dropbox access token for shared link is blank.'
                    );
                }


                HttpRequest shareReq =
                        new HttpRequest();


                shareReq.setEndpoint(
                        'https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'
                );

                shareReq.setMethod('POST');

                shareReq.setHeader(
                        'Authorization',
                        'Bearer ' + shareToken
                );

                shareReq.setHeader(
                        'Content-Type',
                        'application/json'
                );

                shareReq.setBody(
                        JSON.serialize(
                                new Map<String, Object>{
                                        'path' => uploadedPath
                                }
                        )
                );


                HttpResponse shareRes =
                        http.send(shareReq);


                String sharedUrl;


                /*
                 * ---------------------------------------------
                 * Shared link created successfully
                 * ---------------------------------------------
                 */

                if (shareRes.getStatusCode() >= 200 &&
                        shareRes.getStatusCode() < 300) {

                    Map<String, Object> shareResult =
                            (Map<String, Object>)
                                    JSON.deserializeUntyped(
                                            shareRes.getBody()
                                    );


                    sharedUrl =
                            (String) shareResult.get('url');
                }


                /*
                 * ---------------------------------------------
                 * Shared link creation failed
                 * ---------------------------------------------
                 */

                else {

                    String errorBody =
                            shareRes.getBody();


                    if (errorBody != null &&
                            errorBody.contains(
                                    'shared_link_already_exists'
                            )) {

                        String listToken =
                                VMT_DropboxTokenService.getAccessToken();


                        if (String.isBlank(listToken)) {

                            throw new CalloutException(
                                    'Dropbox access token for existing shared link is blank.'
                            );
                        }


                        HttpRequest listReq =
                                new HttpRequest();


                        listReq.setEndpoint(
                                'https://api.dropboxapi.com/2/sharing/list_shared_links'
                        );

                        listReq.setMethod('POST');

                        listReq.setHeader(
                                'Authorization',
                                'Bearer ' + listToken
                        );

                        listReq.setHeader(
                                'Content-Type',
                                'application/json'
                        );

                        listReq.setBody(
                                JSON.serialize(
                                        new Map<String, Object>{
                                                'path' => uploadedPath,
                                                'direct_only' => true
                                        }
                                )
                        );


                        HttpResponse listRes =
                                http.send(listReq);


                        if (listRes.getStatusCode() >= 200 &&
                                listRes.getStatusCode() < 300) {

                            Map<String, Object> listResult =
                                    (Map<String, Object>)
                                            JSON.deserializeUntyped(
                                                    listRes.getBody()
                                            );


                            List<Object> links =
                                    (List<Object>)
                                            listResult.get('links');


                            if (links != null &&
                                    !links.isEmpty()) {

                                Map<String, Object> firstLink =
                                        (Map<String, Object>)
                                                links[0];


                                sharedUrl =
                                        (String) firstLink.get('url');
                            }
                        }

                        else {

                            throw new CalloutException(
                                    'Failed to retrieve existing Dropbox shared link: '
                                            + listRes.getBody()
                            );
                        }
                    }

                    else {

                        throw new CalloutException(
                                'Dropbox shared-link creation failed: '
                                        + errorBody
                        );
                    }
                }


                /*
                 * ---------------------------------------------
                 * Validate shared URL
                 * ---------------------------------------------
                 */

                if (String.isBlank(sharedUrl)) {

                    throw new CalloutException(
                            'Dropbox did not return a shared URL for '
                                    + documentId
                    );
                }


                /*
                 * ---------------------------------------------
                 * Create ONE FileLink__c per CDL
                 * ---------------------------------------------
                 */

                Integer preparedFileLinkCount = 0;


                for (ContentDocumentLink cdl : relatedLinks) {

                    if (cdl.LinkedEntityId == null) {
                        continue;
                    }


                    FileLink__c fl =
                            new FileLink__c();


                    /*
                     * -----------------------------------------
                     * Relationship fields for THIS CDL only
                     * -----------------------------------------
                     */

                    Id fileLinkCaseId;
                    Id fileLinkEmailId;
                    Id fileLinkMieterId;
                    Id fileLinkMietvertragId;

                    String fileLinkCaseNumber;


                    /*
                     * -----------------------------------------
                     * EmailMessage
                     * -----------------------------------------
                     */

                    if (cdl.LinkedEntityId.getSObjectType() ==
                            EmailMessage.SObjectType) {

                        EmailMessage em =
                                emailMap.get(cdl.LinkedEntityId);


                        if (em != null) {

                            fileLinkEmailId =
                                    em.Id;


                            /*
                             * Email -> Case
                             */

                            if (em.ParentId != null) {

                                fileLinkCaseId =
                                        em.ParentId;


                                if (em.Parent != null) {

                                    fileLinkCaseNumber =
                                            em.Parent.CaseNumber;
                                }
                            }


                            /*
                             * Email -> Mieter Account
                             */

                            if (em.RelatedToId != null &&
                                    em.RelatedToId.getSObjectType() ==
                                            Account.SObjectType) {

                                fileLinkMieterId =
                                        em.RelatedToId;
                            }
                        }
                    }


                    /*
                     * -----------------------------------------
                     * Direct Case
                     * -----------------------------------------
                     */

                    else if (
                            cdl.LinkedEntityId.getSObjectType() ==
                                    Case.SObjectType
                    ) {

                        fileLinkCaseId =
                                cdl.LinkedEntityId;


                        Case linkedCase =
                                caseMap.get(cdl.LinkedEntityId);


                        if (linkedCase != null) {

                            fileLinkCaseNumber =
                                    linkedCase.CaseNumber;
                        }
                    }


                    /*
                     * -----------------------------------------
                     * Direct Account / Mieter
                     * -----------------------------------------
                     */

                    else if (
                            cdl.LinkedEntityId.getSObjectType() ==
                                    Account.SObjectType
                    ) {

                        /*
                         * This ContentDocumentLink itself points
                         * directly to the Mieter Account.
                         */

                        if (accountMap.containsKey(
                                cdl.LinkedEntityId
                        )) {

                            fileLinkMieterId =
                                    cdl.LinkedEntityId;
                        }
                    }


                    /*
                     * -----------------------------------------
                     * Mietvertrag
                     * -----------------------------------------
                     */

                    else if (
                            cdl.LinkedEntityId.getSObjectType() ==
                                    Mietvertrag__c.SObjectType
                    ) {

                        fileLinkMietvertragId =
                                cdl.LinkedEntityId;
                    }


                    /*
                     * -----------------------------------------
                     * FileLink Name
                     * -----------------------------------------
                     */

                    if (String.isNotBlank(fileLinkCaseNumber)) {

                        fileLinkCaseNumber =
                                fileLinkCaseNumber.replaceAll(
                                        '[^a-zA-Z0-9_-]',
                                        '_'
                                );
                    }


                    String fileLinkName =
                            (String.isNotBlank(fileLinkCaseNumber)
                                    ? 'Case:' + fileLinkCaseNumber + '_'
                                    : '')
                                    +
                                    (fileLinkMieterId != null
                                            ? 'MieterId:' + fileLinkMieterId + '_'
                                            : '')
                                    +
                                    (fileLinkMietvertragId != null
                                            ? 'MVId:' + fileLinkMietvertragId + '_'
                                            : '')
                                    +
                                    datetimeString
                                    + '_'
                                    + originalName;


                    fl.Name =
                            fileLinkName.substring(
                                    0,
                                    Math.min(
                                            80,
                                            fileLinkName.length()
                                    )
                            );


                    /*
                     * Dropbox fields
                     */

                    fl.DropboxLink__c =
                            sharedUrl;

                    fl.DropboxPath__c =
                            uploadedPath;


                    /*
                     * Salesforce relationship fields
                     */

                    fl.Case__c =
                            fileLinkCaseId;

                    fl.RelatedEmailId__c =
                            fileLinkEmailId;

                    fl.Mietvertrag__c =
                            fileLinkMietvertragId;

                    fl.Mieter__c =
                            fileLinkMieterId;


                    /*
                     * Add FileLink and corresponding document
                     * ID at exactly the same index.
                     */

                    fileLinksToInsert.add(fl);

                    fileLinkDocumentIds.add(documentId);

                    preparedFileLinkCount++;
                }


                /*
                 * Sanity check.
                 */

                if (preparedFileLinkCount == 0) {

                    System.debug(
                            'No FileLink__c records prepared for '
                                    + documentId
                                    + '. ContentDocument will remain.'
                    );
                }
            }


            catch (Exception ex) {

                /*
                 * Any exception makes this ContentDocument
                 * ineligible for deletion.
                 */

                documentsWithProcessingErrors.add(
                        documentId
                );


                System.debug(
                        'Dropbox Queueable processing error for '
                                + documentId
                                + ': '
                                + ex.getMessage()
                );

                System.debug(
                        ex.getStackTraceString()
                );
            }
        }


        /*
         * -------------------------------------------------
         * STEP 11
         * Insert FileLink__c records
         * -------------------------------------------------
         */

        if (fileLinksToInsert.isEmpty()) {

            System.debug(
                    'No FileLink__c records to insert.'
            );

            return;
        }


        Database.SaveResult[] saveResults =
                Database.insert(
                        fileLinksToInsert,
                        false
                );


        /*
         * -------------------------------------------------
         * STEP 12
         * Count expected and successful FileLinks
         * -------------------------------------------------
         */

        Map<Id, Integer> expectedFileLinkCount =
                new Map<Id, Integer>();

        Map<Id, Integer> successfulFileLinkCount =
                new Map<Id, Integer>();

        Set<Id> documentsWithFailedFileLinks =
                new Set<Id>();


        /*
         * Count expected FileLinks.
         */

        for (Integer i = 0;
                i < fileLinksToInsert.size();
                i++) {

            Id documentId =
                    fileLinkDocumentIds[i];


            if (documentId == null) {
                continue;
            }


            Integer currentExpected =
                    expectedFileLinkCount.containsKey(documentId)
                            ? expectedFileLinkCount.get(documentId)
                            : 0;


            expectedFileLinkCount.put(
                    documentId,
                    currentExpected + 1
            );
        }


        /*
         * Process SaveResults.
         */

        for (Integer i = 0;
                i < saveResults.size();
                i++) {

            Database.SaveResult saveResult =
                    saveResults[i];


            Id documentId =
                    fileLinkDocumentIds[i];


            if (documentId == null) {
                continue;
            }


            if (saveResult.isSuccess()) {

                Integer currentSuccessful =
                        successfulFileLinkCount.containsKey(documentId)
                                ? successfulFileLinkCount.get(documentId)
                                : 0;


                successfulFileLinkCount.put(
                        documentId,
                        currentSuccessful + 1
                );
            }

            else {

                documentsWithFailedFileLinks.add(
                        documentId
                );


                System.debug(
                        'FileLink__c insertion failed for '
                                + 'ContentDocument '
                                + documentId
                );


                for (Database.Error error :
                        saveResult.getErrors()) {

                    System.debug(
                            'FileLink Error StatusCode: '
                                    + error.getStatusCode()
                    );

                    System.debug(
                            'FileLink Error Message: '
                                    + error.getMessage()
                    );

                    System.debug(
                            'FileLink Error Fields: '
                                    + error.getFields()
                    );
                }
            }
        }


        /*
         * -------------------------------------------------
         * STEP 13
         * Determine ContentDocuments safe to delete
         * -------------------------------------------------
         */

        Set<Id> documentsReadyForDeletion =
                new Set<Id>();


        for (Id documentId :
                expectedFileLinkCount.keySet()) {

            Integer expected =
                    expectedFileLinkCount.get(
                            documentId
                    );


            Integer successful =
                    successfulFileLinkCount.containsKey(
                            documentId
                    )
                            ? successfulFileLinkCount.get(
                            documentId
                    )
                            : 0;


            /*
             * A ContentDocument may be deleted ONLY when:
             *
             * 1. No processing exception occurred.
             * 2. No FileLink insert failed.
             * 3. At least one FileLink was prepared.
             * 4. Every expected FileLink was inserted.
             */

            if (!documentsWithProcessingErrors.contains(
                    documentId
            )
                    &&
                    !documentsWithFailedFileLinks.contains(
                            documentId
                    )
                    &&
                    expected > 0
                    &&
                    successful == expected) {

                documentsReadyForDeletion.add(
                        documentId
                );
            }
        }


        /*
         * -------------------------------------------------
         * STEP 14
         * Delete eligible ContentDocuments
         * -------------------------------------------------
         */

        if (documentsReadyForDeletion.isEmpty()) {

            System.debug(
                    'No ContentDocuments are eligible for deletion.'
            );

            return;
        }


        List<ContentDocument> documentsToDelete = [
                SELECT Id
                FROM ContentDocument
                WHERE Id IN :documentsReadyForDeletion
        ];


        if (documentsToDelete.isEmpty()) {

            System.debug(
                    'No eligible ContentDocuments were found.'
            );

            return;
        }


        /*
         * Partial-success delete.
         *
         * One deletion failure must not roll back successful
         * deletions of other ContentDocuments.
         */

        Database.DeleteResult[] deleteResults =
                Database.delete(
                        documentsToDelete,
                        false
                );


        /*
         * -------------------------------------------------
         * STEP 15
         * Check deletion results
         * -------------------------------------------------
         */

        for (Integer i = 0;
                i < deleteResults.size();
                i++) {

            Database.DeleteResult deleteResult =
                    deleteResults[i];


            Id documentId =
                    documentsToDelete[i].Id;


            if (deleteResult.isSuccess()) {

                System.debug(
                        'Successfully deleted ContentDocument '
                                + documentId
                );
            }

            else {

                System.debug(
                        'ContentDocument deletion failed for '
                                + documentId
                );


                for (Database.Error error :
                        deleteResult.getErrors()) {

                    System.debug(
                            'Delete Error StatusCode: '
                                    + error.getStatusCode()
                    );

                    System.debug(
                            'Delete Error Message: '
                                    + error.getMessage()
                    );

                    System.debug(
                            'Delete Error Fields: '
                                    + error.getFields()
                    );
                }
            }
        }
    }
}