
@RestResource(urlMapping='/content-migration/*')
global with sharing class VMT_ContentMigrationRest {

    /*
     * Supported relationship priority:
     *
     * 1. Direct Case
     * 2. EmailMessage whose ParentId is a Case
     * 3. Direct EmailMessage
     * 4. Mietvertrag__c
     * 5. Account
     */

    private static final Integer MAX_FILENAME_LENGTH = 255;

    private static final String DROPBOX_PATH =
            'https://www.dropbox.com/home/SalesforceFiles_AutomatedUpload';


    global class RequestBody {
        public List<Id> contentDocumentIds;
    }


    global class FileInfo {
        public Id contentDocumentId;
        public Id contentVersionId;

        public String originalTitle;
        public String extension;

        public Datetime originalCreatedDate;
        public Integer contentSize;

        public Id linkedEntityId;
        public String linkedEntityType;

        public String caseNumber;

        public String fileName;

        public String status;
        public String message;
    }


    global class ResponseBody {
        public List<FileInfo> files = new List<FileInfo>();
        public List<String> errors = new List<String>();
    }


    @HttpPost
    global static ResponseBody prepareFiles() {

        ResponseBody response = new ResponseBody();

        RequestBody request;


        /*
         * ------------------------------------------------------------
         * 1. Parse request
         * ------------------------------------------------------------
         */

        try {

            request = (RequestBody) JSON.deserialize(
                    RestContext.request.requestBody.toString(),
                    RequestBody.class
            );

        } catch (Exception e) {

            response.errors.add(
                    'Invalid JSON request: ' +
                            e.getMessage()
            );

            return response;
        }


        if (
                request == null ||
                        request.contentDocumentIds == null ||
                        request.contentDocumentIds.isEmpty()
        ) {

            response.errors.add(
                    'contentDocumentIds must contain at least one Salesforce ContentDocument Id.'
            );

            return response;
        }


        /*
         * Remove duplicate IDs while keeping original order.
         */

        List<Id> documentIds = new List<Id>();
        Set<Id> documentIdSet = new Set<Id>();


        for (Id documentId : request.contentDocumentIds) {

            if (
                    documentId != null &&
                            !documentIdSet.contains(documentId)
            ) {

                documentIds.add(documentId);
                documentIdSet.add(documentId);
            }
        }


        if (documentIds.isEmpty()) {

            response.errors.add(
                    'No valid ContentDocument Ids were supplied.'
            );

            return response;
        }


        /*
         * Python sends batches of 50.
         */

        if (documentIds.size() > 200) {

            response.errors.add(
                    'Maximum 200 ContentDocument Ids are allowed per request.'
            );

            return response;
        }


        /*
         * ------------------------------------------------------------
         * 2. Get ContentDocument information
         *
         * IMPORTANT:
         * CreatedDate comes from ContentDocument.
         * This is used for the filename timestamp.
         * ------------------------------------------------------------
         */

        Map<Id, ContentDocument> documentsById =
                new Map<Id, ContentDocument>();


        for (ContentDocument document : [
                SELECT
                        Id,
                        CreatedDate
                FROM ContentDocument
                WHERE Id IN :documentIdSet
        ]) {

            documentsById.put(
                    document.Id,
                    document
            );
        }


        /*
         * ------------------------------------------------------------
         * 3. Get latest ContentVersion
         * ------------------------------------------------------------
         */

        Map<Id, ContentVersion> versionsByDocumentId =
                new Map<Id, ContentVersion>();


        for (ContentVersion version : [
                SELECT
                        Id,
                        ContentDocumentId,
                        Title,
                        FileExtension,
                        ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId IN :documentIdSet
                AND IsLatest = true
        ]) {

            versionsByDocumentId.put(
                    version.ContentDocumentId,
                    version
            );
        }


        /*
         * ------------------------------------------------------------
         * 4. Get ALL ContentDocumentLinks
         *
         * Multiple links are allowed.
         * The priority logic below selects one.
         * ------------------------------------------------------------
         */

        Map<Id, List<ContentDocumentLink>> linksByDocumentId =
                new Map<Id, List<ContentDocumentLink>>();


        for (ContentDocumentLink link : [
                SELECT
                        Id,
                        ContentDocumentId,
                        LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocumentId IN :documentIdSet
        ]) {

            if (
                    !linksByDocumentId.containsKey(
                            link.ContentDocumentId
                    )
            ) {

                linksByDocumentId.put(
                        link.ContentDocumentId,
                        new List<ContentDocumentLink>()
                );
            }


            linksByDocumentId
                    .get(link.ContentDocumentId)
                    .add(link);
        }


        /*
         * ------------------------------------------------------------
         * 5. Collect linked record IDs
         * ------------------------------------------------------------
         */

        Set<Id> caseIds =
                new Set<Id>();

        Set<Id> emailIds =
                new Set<Id>();

        Set<Id> mietvertragIds =
                new Set<Id>();

        Set<Id> accountIds =
                new Set<Id>();


        for (Id documentId : documentIds) {

            List<ContentDocumentLink> links =
                    linksByDocumentId.get(documentId);


            if (links == null) {
                continue;
            }


            for (ContentDocumentLink link : links) {

                if (link.LinkedEntityId == null) {
                    continue;
                }


                Id linkedEntityId =
                        link.LinkedEntityId;


                String objectName =
                        linkedEntityId
                                .getSObjectType()
                                .getDescribe()
                                .getName();


                if (objectName == 'Case') {

                    caseIds.add(
                            linkedEntityId
                    );

                } else if (objectName == 'EmailMessage') {

                    emailIds.add(
                            linkedEntityId
                    );

                } else if (objectName == 'Mietvertrag__c') {

                    mietvertragIds.add(
                            linkedEntityId
                    );

                } else if (objectName == 'Account') {

                    accountIds.add(
                            linkedEntityId
                    );
                }
            }
        }


        /*
         * ------------------------------------------------------------
         * 6. Query EmailMessages INCLUDING ParentId
         *
         * THIS IS THE IMPORTANT FIX.
         *
         * An EmailMessage may be the ContentDocumentLink target,
         * while EmailMessage.ParentId points to the Case.
         * ------------------------------------------------------------
         */

        Map<Id, EmailMessage> emailsById =
                new Map<Id, EmailMessage>();


        if (!emailIds.isEmpty()) {

            emailsById =
                    new Map<Id, EmailMessage>([
                            SELECT
                                    Id,
                                    ParentId
                            FROM EmailMessage
                            WHERE Id IN :emailIds
                    ]);
        }


        /*
         * ------------------------------------------------------------
         * 7. Add Cases referenced by EmailMessage.ParentId
         *
         * Only ParentId values whose object is actually Case
         * are treated as Cases.
         * ------------------------------------------------------------
         */

        for (EmailMessage email : emailsById.values()) {

            if (email.ParentId == null) {
                continue;
            }


            String parentObjectName =
                    email.ParentId
                            .getSObjectType()
                            .getDescribe()
                            .getName();


            if (parentObjectName == 'Case') {

                caseIds.add(
                        email.ParentId
                );
            }
        }


        /*
         * ------------------------------------------------------------
         * 8. Query Cases
         *
         * This now contains:
         *
         * - directly linked Cases
         * - Cases reached through EmailMessage.ParentId
         * ------------------------------------------------------------
         */

        Map<Id, Case> casesById =
                new Map<Id, Case>();


        if (!caseIds.isEmpty()) {

            casesById =
                    new Map<Id, Case>([
                            SELECT
                                    Id,
                                    CaseNumber
                            FROM Case
                            WHERE Id IN :caseIds
                    ]);
        }


        /*
         * ------------------------------------------------------------
         * 9. Query Mietvertrag__c
         * ------------------------------------------------------------
         */

        Map<Id, Mietvertrag__c> mietvertraegeById =
                new Map<Id, Mietvertrag__c>();


        if (!mietvertragIds.isEmpty()) {

            mietvertraegeById =
                    new Map<Id, Mietvertrag__c>([
                            SELECT
                                    Id
                            FROM Mietvertrag__c
                            WHERE Id IN :mietvertragIds
                    ]);
        }


        /*
         * ------------------------------------------------------------
         * 10. Query Accounts
         * ------------------------------------------------------------
         */

        Map<Id, Account> accountsById =
                new Map<Id, Account>();


        if (!accountIds.isEmpty()) {

            accountsById =
                    new Map<Id, Account>([
                            SELECT
                                    Id
                            FROM Account
                            WHERE Id IN :accountIds
                    ]);
        }


        /*
         * ------------------------------------------------------------
         * 11. Build FileLink__c records
         * ------------------------------------------------------------
         */

        List<FileLink__c> recordsToInsert =
                new List<FileLink__c>();

        List<FileInfo> pendingInfos =
                new List<FileInfo>();


        for (Id documentId : documentIds) {

            FileInfo info =
                    new FileInfo();

            info.contentDocumentId =
                    documentId;

            info.status =
                    'ERROR';


            /*
             * Get ContentDocument.
             */

            ContentDocument document =
                    documentsById.get(documentId);


            if (document == null) {

                info.message =
                        'ContentDocument could not be found.';

                response.files.add(info);
                continue;
            }


            /*
             * Get latest ContentVersion.
             */

            ContentVersion version =
                    versionsByDocumentId.get(documentId);


            if (version == null) {

                info.message =
                        'No latest ContentVersion found.';

                response.files.add(info);
                continue;
            }


            info.contentVersionId =
                    version.Id;

            info.originalTitle =
                    version.Title;

            info.extension =
                    version.FileExtension;

            info.originalCreatedDate =
                    document.CreatedDate;

            info.contentSize =
                    version.ContentSize;


            /*
             * Get all links.
             */

            List<ContentDocumentLink> links =
                    linksByDocumentId.get(documentId);


            if (
                    links == null ||
                            links.isEmpty()
            ) {

                info.message =
                        'No ContentDocumentLink found.';

                response.files.add(info);
                continue;
            }


            /*
             * --------------------------------------------------------
             * 12. Select linked record
             *
             * Priority:
             *
             * 1 = direct Case
             * 2 = EmailMessage -> Case
             * 3 = direct EmailMessage
             * 4 = Mietvertrag__c
             * 5 = Account
             * --------------------------------------------------------
             */

            ContentDocumentLink selectedLink;

            Integer selectedPriority =
                    999;

            Id selectedEntityId;

            Id selectedCaseIdFromEmail;

            Boolean selectedIsEmailToCase =
                    false;


            for (
                    ContentDocumentLink link :
                    links
            ) {

                if (link.LinkedEntityId == null) {
                    continue;
                }


                Id entityId =
                        link.LinkedEntityId;


                String objectName =
                        entityId
                                .getSObjectType()
                                .getDescribe()
                                .getName();


                Integer priority;

                Boolean isEmailToCase =
                        false;

                Id caseIdFromEmail;


                /*
                 * ----------------------------------------------------
                 * DIRECT CASE
                 * ----------------------------------------------------
                 */

                if (objectName == 'Case') {

                    priority = 1;
                }


                /*
                 * ----------------------------------------------------
                 * EMAIL MESSAGE
                 *
                 * If EmailMessage.ParentId is a Case, this is treated
                 * as a Case relationship.
                 * ----------------------------------------------------
                 */

                else if (objectName == 'EmailMessage') {

                    EmailMessage email =
                            emailsById.get(entityId);


                    if (
                            email != null &&
                                    email.ParentId != null
                    ) {

                        String parentObjectName =
                                email.ParentId
                                        .getSObjectType()
                                        .getDescribe()
                                        .getName();


                        if (
                                parentObjectName == 'Case' &&
                                        casesById.containsKey(
                                                email.ParentId
                                        )
                        ) {

                            /*
                             * EmailMessage -> Case
                             *
                             * This gets priority 2.
                             */

                            priority = 2;

                            isEmailToCase = true;

                            caseIdFromEmail =
                                    email.ParentId;

                        } else {

                            /*
                             * Ordinary EmailMessage.
                             */

                            priority = 3;
                        }

                    } else {

                        /*
                         * Ordinary EmailMessage with no Case parent.
                         */

                        priority = 3;
                    }
                }


                /*
                 * ----------------------------------------------------
                 * MIETVERTRAG
                 * ----------------------------------------------------
                 */

                else if (objectName == 'Mietvertrag__c') {

                    priority = 4;
                }


                /*
                 * ----------------------------------------------------
                 * ACCOUNT
                 * ----------------------------------------------------
                 */

                else if (objectName == 'Account') {

                    priority = 5;
                }


                /*
                 * Unsupported object.
                 */

                else {

                    continue;
                }


                /*
                 * ----------------------------------------------------
                 * Select the first highest-priority match.
                 *
                 * Direct Case always beats everything.
                 *
                 * For the same priority, the first ContentDocumentLink
                 * returned by Salesforce is retained.
                 *
                 * We deliberately do not compare Salesforce IDs here,
                 * avoiding Apex string-comparison compatibility issues.
                 * ----------------------------------------------------
                 */

                if (priority < selectedPriority) {

                    selectedPriority =
                            priority;

                    selectedLink =
                            link;

                    selectedEntityId =
                            entityId;

                    selectedIsEmailToCase =
                            isEmailToCase;

                    selectedCaseIdFromEmail =
                            caseIdFromEmail;
                }
            }


            if (selectedLink == null) {

                info.message =
                        'No supported linked object found. ' +
                                'Supported objects: Case, EmailMessage, ' +
                                'Mietvertrag__c, Account.';

                response.files.add(info);
                continue;
            }


            /*
             * --------------------------------------------------------
             * 13. Determine final linked entity
             *
             * IMPORTANT:
             *
             * For EmailMessage -> Case:
             *
             * linkedEntityId   = Case.Id
             * linkedEntityType = Case
             *
             * This means the normal Case branch below is used.
             * --------------------------------------------------------
             */

            Id linkedEntityId =
                    selectedLink.LinkedEntityId;

            String objectName;


            if (selectedIsEmailToCase) {

                linkedEntityId =
                        selectedCaseIdFromEmail;

                objectName =
                        'Case';

            } else {

                objectName =
                        selectedLink.LinkedEntityId
                                .getSObjectType()
                                .getDescribe()
                                .getName();
            }


            info.linkedEntityId =
                    linkedEntityId;

            info.linkedEntityType =
                    objectName;


            /*
             * --------------------------------------------------------
             * 14. Timestamp
             *
             * Uses ContentDocument.CreatedDate.
             *
             * Example:
             *
             * 20260925_143721_384
             * --------------------------------------------------------
             */

            String timestamp =
                    formatTimestamp(
                            document.CreatedDate
                    );


            FileLink__c fileLink =
                    new FileLink__c();


            /*
             * --------------------------------------------------------
             * CASE
             *
             * Includes:
             *
             * 1. Direct Case
             * 2. EmailMessage -> Case
             * --------------------------------------------------------
             */

            if (objectName == 'Case') {

                Case c =
                        casesById.get(
                                linkedEntityId
                        );


                if (c == null) {

                    info.message =
                            'Selected Case does not exist.';

                    response.files.add(info);
                    continue;
                }


                info.caseNumber =
                        c.CaseNumber;


                info.fileName =
                        buildFileName(
                                'CASE_' +
                                        c.CaseNumber +
                                        '_' +
                                        timestamp,
                                version.Title,
                                version.FileExtension
                        );


                fileLink.Name =
                        info.fileName;

                fileLink.DropboxPath__c =
                        DROPBOX_PATH;

                fileLink.Case__c =
                        linkedEntityId;
            }


            /*
             * --------------------------------------------------------
             * EMAIL MESSAGE
             *
             * This branch is reached ONLY when the EmailMessage does
             * NOT have a Case parent.
             * --------------------------------------------------------
             */

            else if (objectName == 'EmailMessage') {

                EmailMessage email =
                        emailsById.get(
                                linkedEntityId
                        );


                if (email == null) {

                    info.message =
                            'Selected EmailMessage does not exist.';

                    response.files.add(info);
                    continue;
                }


                info.fileName =
                        buildFileName(
                                'EMAIL_' +
                                        String.valueOf(
                                                linkedEntityId
                                        ) +
                                        '_' +
                                        timestamp,
                                version.Title,
                                version.FileExtension
                        );


                fileLink.Name =
                        info.fileName;

                fileLink.DropboxPath__c =
                        DROPBOX_PATH;


                /*
                 * Assumes RelatedEmailId__c is a Text field.
                 *
                 * If it is a Lookup to EmailMessage, change this to:
                 *
                 * fileLink.RelatedEmailId__c =
                 *         linkedEntityId;
                 */

                fileLink.RelatedEmailId__c =
                        String.valueOf(
                                linkedEntityId
                        );
            }


            /*
             * --------------------------------------------------------
             * MIETVERTRAG
             * --------------------------------------------------------
             */

            else if (objectName == 'Mietvertrag__c') {

                Mietvertrag__c mietvertrag =
                        mietvertraegeById.get(
                                linkedEntityId
                        );


                if (mietvertrag == null) {

                    info.message =
                            'Selected Mietvertrag__c does not exist.';

                    response.files.add(info);
                    continue;
                }


                info.fileName =
                        buildFileName(
                                'MIETVERTRAG_' +
                                        String.valueOf(
                                                linkedEntityId
                                        ) +
                                        '_' +
                                        timestamp,
                                version.Title,
                                version.FileExtension
                        );


                fileLink.Name =
                        info.fileName;

                fileLink.DropboxPath__c =
                        DROPBOX_PATH;

                fileLink.Mietvertrag__c =
                        linkedEntityId;
            }


            /*
             * --------------------------------------------------------
             * ACCOUNT / MIETER
             * --------------------------------------------------------
             */

            else if (objectName == 'Account') {

                Account account =
                        accountsById.get(
                                linkedEntityId
                        );


                if (account == null) {

                    info.message =
                            'Selected Account does not exist.';

                    response.files.add(info);
                    continue;
                }


                info.fileName =
                        buildFileName(
                                'MIETER_' +
                                        String.valueOf(
                                                linkedEntityId
                                        ) +
                                        '_' +
                                        timestamp,
                                version.Title,
                                version.FileExtension
                        );


                fileLink.Name =
                        info.fileName;

                fileLink.DropboxPath__c =
                        DROPBOX_PATH;

                fileLink.Mieter__c =
                        linkedEntityId;
            }


            /*
             * Add record for insertion.
             */

            recordsToInsert.add(
                    fileLink
            );

            pendingInfos.add(
                    info
            );
        }


        /*
         * ------------------------------------------------------------
         * 15. Insert FileLink__c records
         *
         * allOrNone = false
         * ------------------------------------------------------------
         */

        if (!recordsToInsert.isEmpty()) {

            Database.SaveResult[] saveResults =
                    Database.insert(
                            recordsToInsert,
                            false
                    );


            for (
                    Integer i = 0;
                    i < saveResults.size();
                    i++
            ) {

                Database.SaveResult result =
                        saveResults[i];

                FileInfo info =
                        pendingInfos[i];


                if (result.isSuccess()) {

                    info.status =
                            'READY';

                    info.message =
                            'FileLink__c created successfully.';

                } else {

                    info.status =
                            'ERROR';


                    List<String> errorMessages =
                            new List<String>();


                    for (
                            Database.Error error :
                            result.getErrors()
                    ) {

                        errorMessages.add(
                                error.getStatusCode() +
                                        ': ' +
                                        error.getMessage()
                        );
                    }


                    info.message =
                            String.join(
                                    errorMessages,
                                    ' | '
                            );
                }


                response.files.add(
                        info
                );
            }
        }


        return response;
    }


    /*
     * ================================================================
     * Timestamp
     *
     * Example:
     *
     * 20260925_143721_384
     * ================================================================
     */

    private static String formatTimestamp(
            Datetime value
    ) {

        return value.format(
                'yyyyMMdd_HHmmss_SSS'
        );
    }


    /*
     * ================================================================
     * Build final filename
     *
     * Example:
     *
     * CASE_00012345_20260925_143721_384_Invoice_John_Smith.pdf
     *
     * Maximum length: 255 characters.
     * ================================================================
     */

    private static String buildFileName(
            String prefix,
            String originalTitle,
            String extension
    ) {

        String safePrefix =
                sanitizeFileNamePart(
                        prefix
                );


        String safeTitle =
                sanitizeFileNamePart(
                        originalTitle
                );


        String safeExtension =
                sanitizeExtension(
                        extension
                );


        String extensionPart =
                '';


        if (
                !String.isBlank(
                        safeExtension
                )
        ) {

            extensionPart =
                    '.' +
                            safeExtension;
        }


        String separator =
                '_';


        String fullName =
                safePrefix +
                        separator +
                        safeTitle +
                        extensionPart;


        /*
         * Already within limit.
         */

        if (
                fullName.length() <=
                        MAX_FILENAME_LENGTH
        ) {

            return fullName;
        }


        /*
         * Truncate only the original title.
         * The prefix and timestamp are preserved.
         */

        Integer availableTitleLength =
                MAX_FILENAME_LENGTH -
                        safePrefix.length() -
                        separator.length() -
                        extensionPart.length();


        if (
                availableTitleLength <= 0
        ) {

            String fallback =
                    safePrefix;


            if (
                    fallback.length() >
                            MAX_FILENAME_LENGTH
            ) {

                fallback =
                        fallback.substring(
                                0,
                                MAX_FILENAME_LENGTH
                        );
            }


            return fallback;
        }


        if (
                safeTitle.length() >
                        availableTitleLength
        ) {

            safeTitle =
                    safeTitle.substring(
                            0,
                            availableTitleLength
                    );
        }


        safeTitle =
                trimWindowsTrailingCharacters(
                        safeTitle
                );


        if (
                String.isBlank(
                        safeTitle
                )
        ) {

            safeTitle =
                    'file';
        }


        fullName =
                safePrefix +
                        separator +
                        safeTitle +
                        extensionPart;


        /*
         * Final safety check.
         */

        if (
                fullName.length() >
                        MAX_FILENAME_LENGTH
        ) {

            fullName =
                    fullName.substring(
                            0,
                            MAX_FILENAME_LENGTH
                    );


            fullName =
                    trimWindowsTrailingCharacters(
                            fullName
                    );
        }


        return fullName;
    }


    /*
     * ================================================================
     * Sanitize filename part
     *
     * Windows-invalid characters:
     *
     * < > : " / \ | ? *
     *
     * Control characters are replaced with "_".
     * ================================================================
     */

    private static String sanitizeFileNamePart(
            String value
    ) {

        if (
                String.isBlank(value)
        ) {

            return 'file';
        }


        String result =
                '';


        for (
                Integer i = 0;
                i < value.length();
                i++
        ) {

            String character =
                    value.substring(
                            i,
                            i + 1
                    );


            Integer code =
                    character.charAt(0);


            /*
             * Control characters.
             */

            if (
                    code < 32
            ) {

                result += '_';
                continue;
            }


            /*
             * Windows-invalid characters.
             */

            if (
                    character == '<' ||
                            character == '>' ||
                            character == ':' ||
                            character == '"' ||
                            character == '/' ||
                            character == '\\' ||
                            character == '|' ||
                            character == '?' ||
                            character == '*'
            ) {

                result += '_';

            } else {

                result += character;
            }
        }


        result =
                trimWindowsTrailingCharacters(
                        result
                );


        if (
                String.isBlank(result)
        ) {

            return 'file';
        }


        return result;
    }


    /*
     * ================================================================
     * Sanitize extension
     * ================================================================
     */

    private static String sanitizeExtension(
            String extension
    ) {

        if (
                String.isBlank(extension)
        ) {

            return '';
        }


        String result =
                sanitizeFileNamePart(
                        extension
                );


        /*
         * Remove leading dots.
         */

        while (
                result.startsWith('.')
        ) {

            result =
                    result.substring(1);
        }


        return result.toLowerCase();
    }


    /*
     * ================================================================
     * Windows filenames cannot end with a space or period.
     * ================================================================
     */

    private static String trimWindowsTrailingCharacters(
            String value
    ) {

        String result =
                value;


        while (
                !String.isBlank(result) &&
                        (
                                result.endsWith(' ') ||
                                        result.endsWith('.')
                        )
        ) {

            result =
                    result.substring(
                            0,
                            result.length() - 1
                    );
        }


        return result;
    }
}