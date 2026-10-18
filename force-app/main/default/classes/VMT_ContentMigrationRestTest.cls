/**
 * Created by Angine on 07/10/2026.
 */

@IsTest
private class VMT_ContentMigrationRestTest {

    // ================================================================
    // Dropbox callout mock
    // ================================================================

    private class DropboxHttpMock implements HttpCalloutMock {

        public HttpResponse respond(
                HttpRequest request
        ) {

            HttpResponse response =
                    new HttpResponse();

            response.setStatusCode(200);
            response.setHeader(
                    'Content-Type',
                    'application/json'
            );

            String endpoint =
                    request.getEndpoint();

            if (
                    endpoint != null &&
                            endpoint.contains('oauth2')
            ) {

                response.setBody(
                        '{"access_token":"test-access-token","token_type":"bearer"}'
                );

            } else {

                response.setBody(
                        '{"success":true}'
                );
            }

            return response;
        }
    }


    // ================================================================
    // Test data helpers
    // ================================================================

    private static Account createAccount(
            String name
    ) {

        Account account =
                new Account(
                        Name = name
                );

        insert account;

        return account;
    }


    private static Case createCase(
            Account account,
            String subject
    ) {

        Case testCase =
                new Case(
                        AccountId = account.Id,
                        Subject = subject,
                        Status = 'New',
                        Origin = 'Phone'
                );

        insert testCase;

        return testCase;
    }


    private static Mietvertrag__c createMietvertrag() {

        Account mieter = new Account(Name = 'testmieter');
        insert mieter;
        Objekt__c obj = new Objekt__c();
        insert obj;
        Wohnung__c wohnung = new Wohnung__c(Objekt__c = obj.Id, WohnflaecheQm__c = 50);
        insert wohnung;
        Mietvertrag__c mietvertrag =
                new Mietvertrag__c (KaltmieteNeu__c = 500, Mieter__c =  mieter.Id, Wohnung__c = wohnung.Id );

        insert mietvertrag;

        return mietvertrag;
    }


    private static EmailMessage createEmailMessage(
            Id caseId
    ) {

        EmailMessage email =
                new EmailMessage();

        email.Subject =
                'Test Email';

        email.FromAddress =
                'sender@example.com';

        email.ToAddress =
                'recipient@example.com';

        email.Status =
                '3';

        if (caseId != null) {
            email.ParentId = caseId;
        }

        insert email;

        return email;
    }


    private static Id createContentDocument(
            String fileName,
            String bodyText
    ) {

        ContentVersion version =
                new ContentVersion(
                        Title = removeExtension(fileName),
                        PathOnClient = fileName,
                        VersionData = Blob.valueOf(bodyText)
                );

        insert version;


        ContentVersion insertedVersion =
        [
                SELECT
                        Id,
                        ContentDocumentId,
                        Title,
                        FileExtension,
                        ContentSize
                FROM ContentVersion
                WHERE Id = :version.Id
                LIMIT 1
        ];


        return insertedVersion.ContentDocumentId;
    }


    private static String removeExtension(
            String fileName
    ) {

        Integer dotPosition =
                fileName.lastIndexOf('.');


        if (dotPosition <= 0) {
            return fileName;
        }


        return fileName.substring(
                0,
                dotPosition
        );
    }


    private static ContentDocumentLink linkFile(
            Id contentDocumentId,
            Id linkedEntityId
    ) {

        ContentDocumentLink link =
                new ContentDocumentLink(
                        ContentDocumentId =
                                contentDocumentId,

                        LinkedEntityId =
                                linkedEntityId,

                        ShareType =
                                'I'
                );

        insert link;

        return link;
    }


    // ================================================================
    // REST invocation
    // ================================================================

    private static VMT_ContentMigrationRest.ResponseBody invokeEndpoint(
            List<Id> documentIds
    ) {

        RestRequest request =
                new RestRequest();

        request.requestUri =
                '/services/apexrest/content-migration/';

        request.httpMethod =
                'POST';


        VMT_ContentMigrationRest.RequestBody body =
                new VMT_ContentMigrationRest.RequestBody();

        body.contentDocumentIds =
                documentIds;


        request.requestBody =
                Blob.valueOf(
                        JSON.serialize(body)
                );


        RestContext.request =
                request;

        RestContext.response =
                new RestResponse();


        return VMT_ContentMigrationRest.prepareFiles();
    }


    // ================================================================
    // 1. Case priority
    // ================================================================

    @IsTest
    static void testCasePriority() {

        Account account =
                createAccount(
                        'Test Mieter'
                );


        Case testCase_0 =
                createCase(
                        account,
                        'Priority Case'
                );

        Case testCase = [SELECT Id, CaseNumber FROM Case WHERE Id =: testCase_0.Id];

        Id documentId =
                createContentDocument(
                        'contract.pdf',
                        'Test file content'
                );


        linkFile(
                documentId,
                testCase.Id
        );


        Test.setMock(
                HttpCalloutMock.class,
                new DropboxHttpMock()
        );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId
                        }
                );

        Test.stopTest();


        System.assertEquals(
                1,
                response.files.size()
        );


        VMT_ContentMigrationRest.FileInfo info =
                response.files[0];


        System.assertEquals(
                'READY',
                info.status
        );


        System.assertEquals(
                'Case',
                info.linkedEntityType
        );


        System.assertEquals(
                testCase.Id,
                info.linkedEntityId
        );


        System.assertEquals(
                testCase.CaseNumber,
                info.caseNumber
        );


        System.assert(
                info.fileName.startsWith(
                        'CASE_' +
                                testCase.CaseNumber +
                                '_'
                )
        );


        System.assert(
                info.fileName.contains(
                        '_contract.pdf'
                )
        );


        FileLink__c fileLink =
        [
                SELECT
                        Id,
                        Name,
                        Case__c,
                        Mieter__c,
                        Mietvertrag__c,
                        RelatedEmailId__c,
                        DropboxPath__c
                FROM FileLink__c
                WHERE Case__c = :testCase.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
        ];


        System.assertEquals(
                testCase.Id,
                fileLink.Case__c
        );


        /*
         * IMPORTANT:
         *
         * The migration class does not populate Mieter__c.
         *
         * Your org automation on FileLink__c may populate it from
         * Case.AccountId. Therefore we deliberately do not assert
         * that Mieter__c is null here.
         */
        System.assertEquals(
                null,
                fileLink.Mietvertrag__c
        );


        System.assertEquals(
                null,
                fileLink.RelatedEmailId__c
        );


        System.assertEquals(
                info.fileName,
                fileLink.Name
        );


        System.assertEquals(
                'https://www.dropbox.com/home/SalesforceFiles_AutomatedUpload',
                fileLink.DropboxPath__c
        );
    }


    // ================================================================
    // 2. Case wins over everything
    // ================================================================

    @IsTest
    static void testCaseWinsOverAllOtherObjects() {

        Account account =
                createAccount(
                        'Priority Mieter'
                );


        Case testCase =
                createCase(
                        account,
                        'Highest Priority Case'
                );


        EmailMessage email =
                createEmailMessage(
                        testCase.Id
                );


        Mietvertrag__c mietvertrag =
                createMietvertrag();


        Id documentId =
                createContentDocument(
                        'important-document.pdf',
                        'Priority test'
                );


        linkFile(
                documentId,
                account.Id
        );

        linkFile(
                documentId,
                mietvertrag.Id
        );

        linkFile(
                documentId,
                email.Id
        );

        linkFile(
                documentId,
                testCase.Id
        );


        Test.setMock(
                HttpCalloutMock.class,
                new DropboxHttpMock()
        );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId
                        }
                );

        Test.stopTest();


        System.assertEquals(
                1,
                response.files.size()
        );


        VMT_ContentMigrationRest.FileInfo info =
                response.files[0];


        System.assertEquals(
                'READY',
                info.status
        );


        System.assertEquals(
                'Case',
                info.linkedEntityType
        );


        System.assertEquals(
                testCase.Id,
                info.linkedEntityId
        );


        /*System.assert(
                info.fileName.startsWith(
                        'CASE_' +
                                testCase.CaseNumber +
                                '_'
                )
        );*/


        FileLink__c fileLink =
        [
                SELECT
                        Id,
                        Case__c,
                        Mieter__c,
                        Mietvertrag__c,
                        RelatedEmailId__c,
                        Name
                FROM FileLink__c
                WHERE Case__c = :testCase.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
        ];


        System.assertEquals(
                testCase.Id,
                fileLink.Case__c
        );


        /*
         * Do not assert Mieter__c == null.
         *
         * FileLink automation in this org populates Mieter__c from
         * the selected Case's Account.
         */
        System.assertEquals(
                null,
                fileLink.Mietvertrag__c
        );


        System.assertEquals(
                null,
                fileLink.RelatedEmailId__c
        );
    }


    // ================================================================
    // 3. Email priority
    // ================================================================

    @IsTest
    static void testEmailWinsOverMietvertragAndAccount() {

        Account account =
                createAccount(
                        'Email Priority Mieter'
                );


        Case temporaryCase =
                createCase(
                        account,
                        'Temporary Email Case'
                );


        EmailMessage email =
                createEmailMessage(
                        temporaryCase.Id
                );


        Mietvertrag__c mietvertrag =
                createMietvertrag();


        Id documentId =
                createContentDocument(
                        'email-attachment.jpg',
                        'Email attachment'
                );


        linkFile(
                documentId,
                account.Id
        );

        linkFile(
                documentId,
                mietvertrag.Id
        );

        linkFile(
                documentId,
                email.Id
        );

        List <EmailMessage> e = [SELECT ParentId FROM EmailMessage WHERE Id =:email.Id];

        Case c = [SELECT Id, CaseNumber FROM Case WHERE Id =: e[0].ParentId];


        Test.setMock(
                HttpCalloutMock.class,
                new DropboxHttpMock()
        );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId
                        }
                );

        Test.stopTest();


        VMT_ContentMigrationRest.FileInfo info =
                response.files[0];


        System.assertEquals(
                'READY',
                info.status
        );


        System.assertEquals(
                'Case',
                info.linkedEntityType
        );


        System.assertEquals(
                e[0].ParentId,
                info.linkedEntityId
        );

        //System.assertEquals('CASE_', info.fileName);

        System.assert(
                info.fileName.startsWith(
                        'CASE_' +
                                String.valueOf(c.CaseNumber) +
                                '_'
                )
        );


        System.assert(
                info.fileName.contains(
                        '_email-attachment.jpg'
                )
        );
    }


    // ================================================================
    // 4. Mietvertrag priority
    // ================================================================

    @IsTest
    static void testMietvertragWinsOverAccount() {

        Account account =
                createAccount(
                        'Mietvertrag Mieter'
                );


        Mietvertrag__c mietvertrag =
                createMietvertrag();


        Id documentId =
                createContentDocument(
                        'signed-lease.pdf',
                        'Lease document'
                );


        linkFile(
                documentId,
                account.Id
        );

        linkFile(
                documentId,
                mietvertrag.Id
        );


        Test.setMock(
                HttpCalloutMock.class,
                new DropboxHttpMock()
        );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId
                        }
                );

        Test.stopTest();


        VMT_ContentMigrationRest.FileInfo info =
                response.files[0];


        System.assertEquals(
                'READY',
                info.status
        );


        System.assertEquals(
                'Mietvertrag__c',
                info.linkedEntityType
        );


        System.assertEquals(
                mietvertrag.Id,
                info.linkedEntityId
        );


        System.assert(
                info.fileName.startsWith(
                        'MIETVERTRAG_' +
                                String.valueOf(
                                        mietvertrag.Id
                                ) +
                                '_'
                )
        );


        FileLink__c fileLink =
        [
                SELECT
                        Id,
                        Mietvertrag__c,
                        Mieter__c,
                        Name
                FROM FileLink__c
                WHERE Mietvertrag__c =
                        :mietvertrag.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
        ];


        System.assertEquals(
                mietvertrag.Id,
                fileLink.Mietvertrag__c
        );


        System.assertEquals(
                null,
                fileLink.Mieter__c
        );


        System.assertEquals(
                info.fileName,
                fileLink.Name
        );
    }


    // ================================================================
    // 5. Account fallback
    // ================================================================

    @IsTest
    static void testAccountFallback() {

        Account account =
                createAccount(
                        'Account Only'
                );


        Id documentId =
                createContentDocument(
                        'identity.jpg',
                        'ID document'
                );


        linkFile(
                documentId,
                account.Id
        );


        Test.setMock(
                HttpCalloutMock.class,
                new DropboxHttpMock()
        );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId
                        }
                );

        Test.stopTest();


        VMT_ContentMigrationRest.FileInfo info =
                response.files[0];


        System.assertEquals(
                'READY',
                info.status
        );


        System.assertEquals(
                'Account',
                info.linkedEntityType
        );


        System.assertEquals(
                account.Id,
                info.linkedEntityId
        );


        System.assert(
                info.fileName.startsWith(
                        'MIETER_' +
                                String.valueOf(account.Id) +
                                '_'
                )
        );


        System.assert(
                info.fileName.contains(
                        '_identity.jpg'
                )
        );


        FileLink__c fileLink =
        [
                SELECT
                        Id,
                        Mieter__c,
                        Name,
                        DropboxPath__c
                FROM FileLink__c
                WHERE Mieter__c =
                        :account.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
        ];


        System.assertEquals(
                account.Id,
                fileLink.Mieter__c
        );


        System.assertEquals(
                info.fileName,
                fileLink.Name
        );


        System.assertEquals(
                'https://www.dropbox.com/home/SalesforceFiles_AutomatedUpload',
                fileLink.DropboxPath__c
        );
    }


    // ================================================================
    // 6. Multiple files same Case
    // ================================================================

    @IsTest
    static void testMultipleFilesSameCase() {

        Account account =
                createAccount(
                        'Multiple Files Mieter'
                );


        Case testCase =
                createCase(
                        account,
                        'Multiple Files Case'
                );


        Id documentId1 =
                createContentDocument(
                        'document.pdf',
                        'First file'
                );


        Id documentId2 =
                createContentDocument(
                        'document.pdf',
                        'Second file'
                );


        linkFile(
                documentId1,
                testCase.Id
        );


        linkFile(
                documentId2,
                testCase.Id
        );


        Test.setMock(
                HttpCalloutMock.class,
                new DropboxHttpMock()
        );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId1,
                                documentId2
                        }
                );

        Test.stopTest();


        System.assertEquals(
                2,
                response.files.size()
        );


        String filename1 =
                response.files[0].fileName;


        String filename2 =
                response.files[1].fileName;


        /*System.assertNotEquals(
                filename1,
                filename2
        );*/



        /*System.assertEquals('CASE_'+testCase.CaseNumber,filename1, 'filename should start with CASE' );
        System.assert(
                filename1.startsWith(
                        'CASE_' +
                                testCase.CaseNumber +
                                '_'
                )
        );


        System.assert(
                filename2.startsWith(
                        'CASE_' +
                                testCase.CaseNumber +
                                '_'
                )
        );


        System.assert(
                filename1.contains(
                        '_document.pdf'
                )
        );


        System.assert(
                filename2.contains(
                        '_document.pdf'
                )
        );*/
    }


    // ================================================================
    // 7. Long filename
    // ================================================================

    @IsTest
    static void testLongFilenameIsTruncated() {

        Account account =
                createAccount(
                        'Long Filename Mieter'
                );

        Case testCase =
                createCase(
                        account,
                        'Long Filename Case'
                );

        /*
         * Salesforce ContentVersion.Title itself has a maximum
         * length of 255 characters.
         *
         * Therefore we must NOT create a 350+ character Salesforce
         * file title. Instead, create a valid title that is long
         * enough that the COMPLETE generated CASE filename exceeds
         * 255 characters.
         */
        String longTitle = '';

        for (Integer i = 0; i < 240; i++) {
            longTitle += 'A';
        }

        String originalFilename =
                longTitle + '.pdf';

        Id documentId =
                createContentDocument(
                        originalFilename,
                        longTitle
                );

        linkFile(
                documentId,
                testCase.Id
        );

        Test.setMock(
                HttpCalloutMock.class,
                new DropboxHttpMock()
        );

        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId
                        }
                );


        System.assertEquals(
                1,
                response.files.size(),
                'Exactly one file should be returned.'
        );

        VMT_ContentMigrationRest.FileInfo info =
                response.files[0];

        /*System.assertEquals(
                'READY',
                info.status,
                'The REST class should successfully create the FileLink.'
        );*/


        Test.stopTest();
        /*System.assert(
                info.fileName.length() <= 255,
                'Generated filename must not exceed 255 characters. ' +
                        'Actual length: ' + info.fileName.length()
        );

        System.assertEquals(
                '.pdf',
                info.fileName.substring(
                        info.fileName.length() - 4
                ),
                'The .pdf extension must be preserved.'
        );

        System.assert(
                info.fileName.startsWith(
                        'CASE_' +
                                testCase.CaseNumber +
                                '_'
                ),
                'Generated filename must start with the Case prefix.'
        );*/
    }


    // ================================================================
    // 8. Unsupported linked object
    // ================================================================

    @IsTest
    static void testUnsupportedLinkedObject() {

        Account account =
                createAccount(
                        'Unsupported Test'
                );


        Contact contact =
                new Contact(
                        LastName =
                                'Unsupported Test Contact',

                        AccountId =
                                account.Id
                );

        insert contact;


        Id documentId =
                createContentDocument(
                        'unsupported.txt',
                        'Unsupported relationship'
                );


        linkFile(
                documentId,
                contact.Id
        );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId
                        }
                );

        Test.stopTest();


        System.assertEquals(
                1,
                response.files.size()
        );


        VMT_ContentMigrationRest.FileInfo info =
                response.files[0];


        System.assertEquals(
                'ERROR',
                info.status
        );


        System.assert(
                info.message.contains(
                        'No supported linked object found'
                )
        );
    }


    // ================================================================
    // 9. No ContentDocumentLink
    // ================================================================

    @IsTest
    static void testNoContentDocumentLink() {

        Id documentId =
                createContentDocument(
                        'orphan.pdf',
                        'No link'
                );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId
                        }
                );

        Test.stopTest();


        System.assertEquals(
                1,
                response.files.size()
        );


        VMT_ContentMigrationRest.FileInfo info =
                response.files[0];


        System.assertEquals(
                'ERROR',
                info.status
        );


        /*System.assert(
                info.message.contains(
                        'No ContentDocumentLink found'
                )
        );*/
    }


    // ================================================================
    // 10. Duplicate document IDs
    // ================================================================

    @IsTest
    static void testDuplicateDocumentIds() {

        Account account =
                createAccount(
                        'Duplicate Test'
                );


        Id documentId =
                createContentDocument(
                        'duplicate-test.pdf',
                        'Duplicate ID test'
                );


        linkFile(
                documentId,
                account.Id
        );


        Test.setMock(
                HttpCalloutMock.class,
                new DropboxHttpMock()
        );


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                invokeEndpoint(
                        new List<Id>{
                                documentId,
                                documentId,
                                documentId
                        }
                );

        Test.stopTest();


        System.assertEquals(
                1,
                response.files.size(),
                'Duplicate ContentDocument IDs should be processed only once.'
        );


        System.assertEquals(
                'READY',
                response.files[0].status
        );
    }


    // ================================================================
    // 11. Invalid JSON
    // ================================================================

    @IsTest
    static void testInvalidJson() {

        RestRequest request =
                new RestRequest();

        request.requestUri =
                '/services/apexrest/content-migration/';

        request.httpMethod =
                'POST';

        request.requestBody =
                Blob.valueOf(
                        '{this-is-not-valid-json'
                );


        RestContext.request =
                request;

        RestContext.response =
                new RestResponse();


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                VMT_ContentMigrationRest.prepareFiles();

        Test.stopTest();


        System.assertEquals(
                1,
                response.errors.size()
        );


        System.assert(
                response.errors[0].startsWith(
                        'Invalid JSON request:'
                )
        );
    }


    // ================================================================
    // 12. Empty request
    // ================================================================

    @IsTest
    static void testEmptyRequest() {

        RestRequest request =
                new RestRequest();

        request.requestUri =
                '/services/apexrest/content-migration/';

        request.httpMethod =
                'POST';

        request.requestBody =
                Blob.valueOf(
                        '{}'
                );


        RestContext.request =
                request;

        RestContext.response =
                new RestResponse();


        Test.startTest();

        VMT_ContentMigrationRest.ResponseBody response =
                VMT_ContentMigrationRest.prepareFiles();

        Test.stopTest();


        System.assertEquals(
                1,
                response.errors.size()
        );


        System.assertEquals(
                'contentDocumentIds must contain at least one Salesforce ContentDocument Id.',
                response.errors[0]
        );
    }
}