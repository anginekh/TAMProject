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
         * STEP 1
         * Query latest versions
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

        System.debug('im here 1 : doc links' + docLinks);
        //ignoring the duplicate cdl, associated with user
        List<ContentDocumentLink> filteredLinks = new List<ContentDocumentLink>();
        for (ContentDocumentLink cdl : docLinks) {
            if (!String.valueOf(cdl.LinkedEntityId).startsWith('005')) {
                filteredLinks.add(cdl);
            }
        }

        docLinks = filteredLinks;

        System.debug('im here 2: filtered doc links' + docLinks);
        /*
         * -------------------------------------------------
         * STEP 3
         * Collect EmailMessage IDs
         * -------------------------------------------------
         */

        Set<Id> emailMessageIds = new Set<Id>();

        Map<Id, List<ContentDocumentLink>> linksByDoc =
                new Map<Id, List<ContentDocumentLink>>();

        for(ContentDocumentLink cdl : docLinks) {

            if(!linksByDoc.containsKey(cdl.ContentDocumentId)) {

                linksByDoc.put(
                        cdl.ContentDocumentId,
                        new List<ContentDocumentLink>()
                );
            }

            linksByDoc.get(cdl.ContentDocumentId).add(cdl);

            if(cdl.LinkedEntityId.getSobjectType() ==
                    EmailMessage.SObjectType) {

                emailMessageIds.add(cdl.LinkedEntityId);
            }
        }

        /*
         * -------------------------------------------------
         * STEP 4
         * Query EmailMessages + Parent Case
         * -------------------------------------------------
         */

        Map<Id, EmailMessage> emailMap =
                new Map<Id, EmailMessage>();

        if(!emailMessageIds.isEmpty()) {

            emailMap = new Map<Id, EmailMessage>([

                    SELECT Id,
                            ParentId,
                            Parent.CaseNumber

                    FROM EmailMessage

                    WHERE Id IN :emailMessageIds
            ]);
        }

        /*
         * -------------------------------------------------
         * STEP 5
         * Prepare inserts
         * -------------------------------------------------
         */

        List<FileLink__c> fileLinksToInsert = new List<FileLink__c>();

        Http http = new Http();

        /*
         * -------------------------------------------------
         * STEP 6
         * Process each file
         * -------------------------------------------------
         */

        for(ContentVersion cv : versions) {

            try {

                /*
                 * ---------------------------------------------
                 * Build file name
                 * ---------------------------------------------
                 */

                String originalName = cv.Title;

                String extension = '';
                if(String.isNotBlank(cv.FileExtension)) {

                    extension += '.' + cv.FileExtension;
                }

                List<ContentDocumentLink> relatedLinks =
                        linksByDoc.get(cv.ContentDocumentId);

                String relatedEmailId;
                String caseId;
                String caseNumber;
                String mieterAccountId;
                String mietvertragId;
                String mietvertragName;
                if(relatedLinks != null) {

                    for(ContentDocumentLink cdl : relatedLinks) {


                        //if related to email
                        if(cdl.LinkedEntityId.getSobjectType() == EmailMessage.SObjectType) {
                            EmailMessage em = emailMap.get( cdl.LinkedEntityId);
                            relatedEmailId = em.Id;
                            //connect to case
                            if (em.ParentId != null){
                                caseId = em.ParentId;
                                caseNumber = String.valueOf(em.Parent.get('CaseNumber'));
                                break;
                                //connect to Mieter
                            }else if (em.RelatedToId != null){
                                mieterAccountId = em.RelatedToId;
                                break;
                            }

                            //if related to automatedprocess (the case of NK) - ignore
                        } else if (cdl.LinkedEntityId == '005J6000000YNkTIAW'){continue;}
                        //if related to Mietvertrag
                        else if (cdl.LinkedEntityId.getSobjectType() == Mietvertrag__c.SObjectType){
                            mietvertragId = cdl.LinkedEntityId;
                            break;
                            //todo: get the MV name
                        }
                    }

                /*
                 * Current DateTime
                 */
                String datetimeString =
                        Datetime.now().format();

                /*
                 * Sanitize filename
                 */
                originalName =
                        originalName.replaceAll(
                                '[^a-zA-Z0-9._-]',
                                '_'
                        );

                caseNumber =
                        caseNumber.replaceAll(
                                '[^a-zA-Z0-9_-]',
                                '_'
                        );

                /*
                 * Final filename
                 */

                //todo: replace mietvertragid with mietvertragname and the same for mieter

                String fileName = (caseNumber!=null? 'Case:'+caseNumber + '_':'') + (mieterAccountId!=null? 'MieterId:'+mieterAccountId+ '_':'') + (mietvertragId!=null?'MVId:'+mietvertragId
                        + '_':'')
                        + datetimeString
                        + '_'
                        + originalName
                        + extension;

                /*
                 * ---------------------------------------------
                 * Dropbox upload path
                 * ---------------------------------------------
                 */

                String dropboxPath =
                        '/SalesforceFiles_AutomatedUpload/' + fileName;

                /*
                 * ---------------------------------------------
                 * Upload file to Dropbox
                 * ---------------------------------------------
                 */

                String token = VMT_DropboxTokenService.getAccessToken();

                HttpRequest uploadReq = new HttpRequest();

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

                uploadReq.setBodyAsBlob(cv.VersionData);

                HttpResponse uploadRes = http.send(uploadReq);

                System.debug(
                        'UPLOAD RESPONSE: ' + uploadRes.getBody()
                );

                if(uploadRes.getStatusCode() < 200 ||
                        uploadRes.getStatusCode() >= 300) {

                    //todo: add error/exception logging
                    System.debug(
                            'Dropbox upload failed: '
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

                /*
                 * ---------------------------------------------
                 * Create shared link
                 * ---------------------------------------------
                 */

                String token1 = VMT_DropboxTokenService.getAccessToken();

                HttpRequest shareReq = new HttpRequest();
                shareReq.setEndpoint(
                        'https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'
                );
                shareReq.setMethod('POST');
                shareReq.setHeader(
                    'Authorization',
                    'Bearer ' + token1
                );
                shareReq.setHeader('Content-Type', 'application/json');
                shareReq.setBody(
                        JSON.serialize(
                                new Map<String, Object>{
                                        'path' => uploadedPath
                                }
                        )
                );

                HttpResponse shareRes = http.send(shareReq);

                String sharedUrl;

                if (shareRes.getStatusCode() >= 200 &&
                        shareRes.getStatusCode() < 300) {

                    Map<String, Object> result =
                            (Map<String, Object>) JSON.deserializeUntyped(
                                    shareRes.getBody()
                            );

                    sharedUrl = (String) result.get('url');
                }
                else {

                    Map<String, Object> errorBody =
                            (Map<String, Object>) JSON.deserializeUntyped(
                                    shareRes.getBody()
                            );

                    String errorJson = JSON.serialize(errorBody);

                    // Shared link already exists
                    String token2 = VMT_DropboxTokenService.getAccessToken();
                    if (errorJson.contains('shared_link_already_exists')) {

                        HttpRequest listReq = new HttpRequest();
                        listReq.setEndpoint(
                                'callout:DropboxAPI_NC/2/sharing/list_shared_links'
                        );
                        listReq.setMethod('POST');
                        listReq.setHeader(
                                'Authorization',
                                'Bearer ' + token2
                        );
                        listReq.setHeader('Content-Type', 'application/json');
                        listReq.setBody(
                                JSON.serialize(
                                        new Map<String, Object>{
                                                'path' => uploadedPath,
                                                'direct_only' => true
                                        }
                                )
                        );

                        HttpResponse listRes = http.send(listReq);

                        if (listRes.getStatusCode() >= 200 &&
                                listRes.getStatusCode() < 300) {

                            Map<String, Object> listResult =
                                    (Map<String, Object>) JSON.deserializeUntyped(
                                            listRes.getBody()
                                    );

                            List<Object> links =
                                    (List<Object>) listResult.get('links');

                            if (!links.isEmpty()) {
                                Map<String, Object> firstLink =
                                        (Map<String, Object>) links[0];

                                sharedUrl = (String) firstLink.get('url');
                            }
                        }
                        else {
                            System.debug(
                                    'Failed to retrieve existing shared link: '
                                            + listRes.getBody()
                            );
                            continue;
                        }
                    }
                    else {
                        System.debug(
                                'Dropbox share failed: ' + shareRes.getBody()
                        );
                        continue;
                    }
                }

                System.debug('Shared URL: ' + sharedUrl);

                /*
                 * ---------------------------------------------
                 * Find related EmailMessage
                 * ---------------------------------------------
                 */

                List<ContentDocumentLink> relatedLinks2 =
                        linksByDoc.get(
                                cv.ContentDocumentId
                        );

                if(relatedLinks2 == null) {
                    continue;
                }

                for(ContentDocumentLink cdl : relatedLinks2) {
                    //if related to email
                    if(cdl.LinkedEntityId.getSobjectType() == EmailMessage.SObjectType) {
                        EmailMessage em = emailMap.get( cdl.LinkedEntityId);
                        relatedEmailId = em.Id;
                        //connect to case
                        if (em.ParentId != null){
                            caseId = em.ParentId;
                            caseNumber = String.valueOf(em.Parent.get('CaseNumber'));
                        //connect to Mieter
                        }else if (em.RelatedToId != null){
                            mieterAccountId = em.RelatedToId;
                        }

                    //if related to automatedprocess (the case of NK) - ignore
                    } else if (cdl.LinkedEntityId == '005J6000000YNkTIAW'){continue;}
                    //if related to Mietvertrag
                    else if (cdl.LinkedEntityId.getSobjectType() == Mietvertrag__c.SObjectType){
                        mietvertragId = cdl.LinkedEntityId;
                        //todo: get the MV name
                        }
                    }

                    /*
                     * -----------------------------------------
                     * Create File_Link__c
                     * -----------------------------------------
                     */



                    FileLink__c fl = new FileLink__c();

                    String fileNameString = (caseNumber!=null? 'Case:'+caseNumber + '_':'') + (mieterAccountId!=null? 'MieterId:'+mieterAccountId+ '_':'') + (mietvertragId!=null?'MVId:'+mietvertragId
                            + '_':'')
                            + datetimeString
                            + '_'
                            + originalName;

                    fl.Name = fileNameString.substring(0,Math.min(80, fileNameString.length()));

                    System.debug('im here '+ fl.Name);

                    fl.DropboxLink__c = sharedUrl;

                    //fl.DropboxFileId__c

                    fl.DropboxPath__c = uploadedPath;

                    fl.Case__c = caseId;

                    fl.RelatedEmailId__c = relatedEmailId;

                    fl.Mietvertrag__c = mietvertragId;

                    fl.Mieter__c = mieterAccountId;

                    fileLinksToInsert.add(fl);
                }

            } catch(Exception ex) {

                System.debug(
                        'Dropbox Queueable Error: '
                                + ex.getMessage()
                );

                System.debug(
                        ex.getStackTraceString()
                );
            }
        }

        /*
         * -------------------------------------------------
         * STEP 7
         * Insert File_Link__c records
         * -------------------------------------------------
         */

        if(!fileLinksToInsert.isEmpty()) {

            insert fileLinksToInsert;
        }
    }
}