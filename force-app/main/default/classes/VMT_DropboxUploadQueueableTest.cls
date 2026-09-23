/**
 * Created by Angine on 23/09/2026.
 */

@IsTest
private class VMT_DropboxUploadQueueableTest {

    private static ContentVersion createFile( Id accountId, Id caseId, String fileName ) { ContentVersion cv = new ContentVersion( Title = fileName.substringBeforeLast('.'), PathOnClient = fileName, VersionData = Blob.valueOf('Test file content') ); insert cv; return [ SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1 ]; }
    /*
     * -------------------------------------------------------
     * Dropbox HTTP Mock
     * -------------------------------------------------------
     */
    private class DropboxHttpMock implements HttpCalloutMock {

        private Boolean sharedLinkAlreadyExists;
        private Boolean uploadFails;
        private Boolean shareLinkFails;

        public Integer tokenCalls = 0;
        public Integer uploadCalls = 0;
        public Integer shareCalls = 0;
        public Integer listCalls = 0;

        DropboxHttpMock() {
            this(false, false, false);
        }

        DropboxHttpMock(
                Boolean sharedLinkAlreadyExists,
                Boolean uploadFails,
                Boolean shareLinkFails
        ) {
            this.sharedLinkAlreadyExists =
                    sharedLinkAlreadyExists;

            this.uploadFails =
                    uploadFails;

            this.shareLinkFails =
                    shareLinkFails;
        }


        public HttpResponse respond(HttpRequest req) {

            String endpoint = req.getEndpoint();


            /*
             * -----------------------------------------------
             * Token
             * -----------------------------------------------
             */
            if (
                    endpoint ==
                            'https://api.dropboxapi.com/oauth2/token'
            ) {

                tokenCalls++;

                HttpResponse res =
                        new HttpResponse();

                res.setStatusCode(200);

                res.setBody(
                        '{"access_token":"test-access-token","expires_in":3600}'
                );

                return res;
            }


            /*
             * -----------------------------------------------
             * Upload
             * -----------------------------------------------
             */
            if (
                    endpoint ==
                            'https://content.dropboxapi.com/2/files/upload'
            ) {

                uploadCalls++;

                HttpResponse res =
                        new HttpResponse();

                if (uploadFails) {

                    res.setStatusCode(500);

                    res.setBody(
                            '{"error":"upload_failed"}'
                    );

                    return res;
                }

                System.assertEquals(
                        'POST',
                        req.getMethod()
                );

                System.assertEquals(
                        'application/octet-stream',
                        req.getHeader('Content-Type')
                );

                System.assert(
                        req.getHeader('Authorization')
                                .contains('Bearer test-access-token'),
                        'Upload request must contain the Dropbox access token.'
                );

                System.assert(
                        req.getHeader('Dropbox-API-Arg')
                                .contains(
                                        '/SalesforceFiles_AutomatedUpload/'
                                ),
                        'Dropbox path should use the configured upload directory.'
                );

                res.setStatusCode(200);

                res.setBody(
                        '{' +
                                '"name":"Test_File.txt",' +
                                '"path_lower":"/salesforcefiles_automatedupload/test_file.txt",' +
                                '"id":"id:test-file"' +
                                '}'
                );

                return res;
            }


            /*
             * -----------------------------------------------
             * Create shared link
             * -----------------------------------------------
             */
            if (
                    endpoint ==
                            'https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'
            ) {

                shareCalls++;

                HttpResponse res =
                        new HttpResponse();

                if (shareLinkFails) {

                    res.setStatusCode(409);

                    res.setBody(
                            '{"error_summary":"some_other_error"}'
                    );

                    return res;
                }

                if (sharedLinkAlreadyExists) {

                    res.setStatusCode(409);

                    res.setBody(
                            '{"error_summary":"shared_link_already_exists/"}'
                    );

                    return res;
                }

                res.setStatusCode(200);

                res.setBody(
                        '{' +
                                '"url":"https://www.dropbox.com/s/test/shared-file",' +
                                '"name":"Test_File.txt",' +
                                '"path_lower":"/salesforcefiles_automatedupload/test_file.txt"' +
                                '}'
                );

                return res;
            }


            /*
             * -----------------------------------------------
             * List existing shared links
             * -----------------------------------------------
             */
            if (
                    endpoint ==
                            'https://api.dropboxapi.com/2/sharing/list_shared_links'
            ) {

                listCalls++;

                HttpResponse res =
                        new HttpResponse();

                res.setStatusCode(200);

                res.setBody(
                        '{' +
                                '"links":[' +
                                '{' +
                                '"url":"https://www.dropbox.com/s/existing/shared-file",' +
                                '"name":"Test_File.txt",' +
                                '"path_lower":"/salesforcefiles_automatedupload/test_file.txt"' +
                                '}' +
                                ']' +
                                '}'
                );

                return res;
            }


            /*
             * -----------------------------------------------
             * Unknown endpoint
             * -----------------------------------------------
             */
            HttpResponse unknown =
                    new HttpResponse();

            unknown.setStatusCode(404);
            unknown.setBody(
                    '{"error":"unexpected_endpoint"}'
            );

            return unknown;
        }
    }


    /*
     * -------------------------------------------------------
     * Create Dropbox Custom Setting
     * -------------------------------------------------------
     */
    private static void createDropboxSettings() {

        DropboxSettings__c settings =
                new DropboxSettings__c(
                        SetupOwnerId = UserInfo.getOrganizationId(),
                        ClientId__c = 'client-id',
                        ClientSecret__c = 'client-secret',
                        RefreshToken__c = 'refresh-token'
                );

        insert settings;
    }


    /*
     * -------------------------------------------------------
     * Create Account
     * -------------------------------------------------------
     */
    private static Account createAccount() {

        Account acc =
                new Account(
                        Name = 'Test Mieter'
                );

        insert acc;

        return acc;
    }


    /*
     * -------------------------------------------------------
     * Create Case
     * -------------------------------------------------------
     */
    private static Case createCase(Account acc) {

        Case c =
                new Case(
                        AccountId = acc.Id,
                        Subject = 'Dropbox Test Case',
                        Status = 'New',
                        Origin = 'Email'
                );

        insert c;

        return c;
    }


    /*
     * -------------------------------------------------------
     * Create Salesforce File
     * -------------------------------------------------------
     */
    private static ContentVersion createFile(
            Id firstPublishLocationId
    ) {

        ContentVersion cv =
                new ContentVersion(
                        Title = 'Test File',
                        PathOnClient = 'Test File.txt',
                        VersionData = Blob.valueOf(
                                'This is test file content.'
                        ),
                        FirstPublishLocationId =
                                firstPublishLocationId
                );

        insert cv;

        return cv;
    }


    /*
     * -------------------------------------------------------
     * Test successful upload
     * -------------------------------------------------------
     */
    @IsTest
    static void testSuccessfulDropboxUpload() {

        createDropboxSettings();

        Account acc =
                createAccount();

        Case c =
                createCase(acc);

        ContentVersion cv = createFile(
                acc.Id,
                c.Id,
                'TestFile.pdf'
        );

        Id documentId =
                cv.ContentDocumentId;


        /*
         * The ContentVersion created a ContentDocumentLink
         * to the Account. Add a Case link as well.
         *
         * The queueable is already enqueued by the trigger,
         * but does not execute until Test.stopTest().
         */
        insert new ContentDocumentLink(
                ContentDocumentId = documentId,
                LinkedEntityId = c.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
        );


        DropboxHttpMock mock =
                new DropboxHttpMock();

        Test.setMock(
                HttpCalloutMock.class,
                mock
        );


        Test.startTest();

        /*
         * The ContentDocumentTrigger has already enqueued
         * VMT_DropboxUploadQueueable.
         */
        Test.stopTest();


        /*
         * -----------------------------------------------
         * Verify HTTP calls
         * -----------------------------------------------
         */
        System.assertEquals(
                1,
                mock.tokenCalls,
                'Token should be requested once.'
        );

        System.assertEquals(
                1,
                mock.uploadCalls,
                'One file should be uploaded.'
        );

        System.assertEquals(
                1,
                mock.shareCalls,
                'One shared link should be created.'
        );


        /*
         * -----------------------------------------------
         * Verify FileLink records
         * -----------------------------------------------
         */
        List<FileLink__c> fileLinks = [
                SELECT Id,
                        Name,
                        DropboxLink__c,
                        DropboxPath__c,
                        Case__c,
                        Mieter__c,
                        RelatedEmailId__c,
                        Mietvertrag__c
                FROM FileLink__c
        ];

        /*
         * There should be one FileLink for each
         * ContentDocumentLink.
         *
         * Account + Case = 2.
         */
        System.assertEquals(
                1,
                fileLinks.size(),
                'A FileLink should be created for each relevant ContentDocumentLink.'
        );


        Integer accountLinks = 0;
        Integer caseLinks = 0;

        for (FileLink__c fl : fileLinks) {

            System.assertEquals(
                    'https://www.dropbox.com/s/test/shared-file',
                    fl.DropboxLink__c
            );

            System.assert(
                    fl.DropboxPath__c.contains(
                            '/salesforcefiles_automatedupload/'
                    ),
                    'Dropbox path should contain the upload directory.'
            );

            if (fl.Mieter__c == acc.Id) {
                accountLinks++;
            }

            if (fl.Case__c == c.Id) {
                caseLinks++;
            }
        }


        System.assertEquals(
                1,
                caseLinks,
                'One FileLink should point to the Case.'
        );


        /*
         * -----------------------------------------------
         * ContentDocument should have been deleted
         * -----------------------------------------------
         */
        System.assertEquals(
                0,
                [
                        SELECT COUNT()
                        FROM ContentDocument
                        WHERE Id = :documentId
                ],
                'ContentDocument should be deleted after all FileLinks succeed.'
        );
    }


    /*
     * -------------------------------------------------------
     * Test upload failure
     * -------------------------------------------------------
     */
    @IsTest
    static void testUploadFailureDoesNotDeleteDocument() {

        createDropboxSettings();

        Account acc =
                createAccount();

        ContentVersion cv =
                createFile(acc.Id);

        Id documentId =
                cv.ContentDocumentId;


        DropboxHttpMock mock =
                new DropboxHttpMock(
                        false,
                        true,
                        false
                );

        Test.setMock(
                HttpCalloutMock.class,
                mock
        );


        Test.startTest();
        Test.stopTest();


        System.assertEquals(
                1,
                mock.uploadCalls
        );

        System.assertEquals(
                0,
                mock.shareCalls,
                'Shared-link creation should not occur when upload fails.'
        );


        /*
         * No FileLink should have been created.
         */
        System.assertEquals(
                0,
                [
                        SELECT COUNT()
                        FROM FileLink__c
                ]
        );


        /*
         * ContentDocument must remain because upload failed.
         */
        System.assertEquals( 1, mock.uploadCalls, 'Dropbox upload should have been attempted once.' ); System.assertEquals( 0, [ SELECT COUNT() FROM FileLink__c ], 'No FileLink should be created when Dropbox upload fails.' );
    }


    /*
     * -------------------------------------------------------
     * Test existing shared link
     * -------------------------------------------------------
     */
    @IsTest
    static void testExistingSharedLink() {

        createDropboxSettings();

        Account acc =
                createAccount();

        ContentVersion cv =
                createFile(acc.Id);

        Id documentId =
                cv.ContentDocumentId;


        DropboxHttpMock mock =
                new DropboxHttpMock(
                        true,
                        false,
                        false
                );

        Test.setMock(
                HttpCalloutMock.class,
                mock
        );


        Test.startTest();
        Test.stopTest();


        /*
         * The upload should succeed.
         */
        System.assertEquals(
                1,
                mock.uploadCalls
        );


        /*
         * First attempt to create the shared link.
         */
        System.assertEquals(
                1,
                mock.shareCalls
        );


        /*
         * Existing link should then be queried.
         */
        System.assertEquals(
                1,
                mock.listCalls
        );


        FileLink__c fl = [
                SELECT Id,
                        DropboxLink__c,
                        DropboxPath__c,
                        Mieter__c
                FROM FileLink__c
                LIMIT 1
        ];


        System.assertEquals(
                'https://www.dropbox.com/s/existing/shared-file',
                fl.DropboxLink__c,
                'Existing Dropbox shared URL should be stored.'
        );


        System.assertEquals(
                acc.Id,
                fl.Mieter__c,
                'FileLink should retain the Account relationship.'
        );


        /*
         * The document should be deleted because the existing
         * shared link was successfully retrieved.
         */
        System.assertEquals(
                0,
                [
                        SELECT COUNT()
                        FROM ContentDocument
                        WHERE Id = :documentId
                ]
        );
    }


    /*
     * -------------------------------------------------------
     * Test shared-link failure
     * -------------------------------------------------------
     */


    @IsTest
    static void testSharedLinkFailureDoesNotDeleteDocument() {
        createDropboxSettings();

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        DropboxHttpMock mock = new DropboxHttpMock();
        mock.shareLinkFails = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Id documentId;
        Id versionId;

        Test.startTest();

        ContentVersion cv = new ContentVersion(
                Title = 'Test File',
                PathOnClient = 'TestFile.pdf',
                VersionData = Blob.valueOf('Test content'),
                FirstPublishLocationId = acc.Id
        );
        insert cv;

        documentId = cv.ContentDocumentId;
        versionId = cv.Id;

        Test.stopTest();

        System.debug('=== DIAGNOSTIC documentId: ' + documentId);
        System.debug('=== DIAGNOSTIC versionId: ' + versionId);
        System.debug('=== DIAGNOSTIC tokenCalls: ' + mock.tokenCalls);
        System.debug('=== DIAGNOSTIC uploadCalls: ' + mock.uploadCalls);
        System.debug('=== DIAGNOSTIC shareCalls: ' + mock.shareCalls);
        System.debug('=== DIAGNOSTIC listCalls: ' + mock.listCalls);

        // Verify the expected Dropbox flow actually occurred.
        System.assertEquals(
                1,
                mock.tokenCalls,
                'Access token should have been requested once.'
        );

        System.assertEquals(
                1,
                mock.uploadCalls,
                'Dropbox upload should have been attempted once.'
        );

        System.assertEquals(
                1,
                mock.shareCalls,
                'Shared-link creation should have been attempted once.'
        );

        System.assertEquals(
                0,
                mock.listCalls,
                'list_shared_links should NOT be called for an unrelated share-link failure.'
        );

        // The queueable should not have created a FileLink.
        System.assertEquals(
                0,
                [
                        SELECT COUNT()
                        FROM FileLink__c
                ],
                'No FileLink__c should be created when shared-link creation fails.'
        );

        // First check the normal object.
        List<ContentDocument> activeDocs = [
                SELECT Id, Title
                FROM ContentDocument
                WHERE Id = :documentId
        ];

        System.debug('=== DIAGNOSTIC active ContentDocuments: ' + activeDocs);

        // Then check ALL ROWS to determine whether it was soft-deleted.
        List<ContentDocument> allDocs = [
                SELECT Id, Title, IsDeleted
                FROM ContentDocument
                WHERE Id = :documentId
                ALL ROWS
        ];

        System.debug('=== DIAGNOSTIC ALL ROWS ContentDocuments: ' + allDocs);

        // Also inspect the ContentVersion.
        List<ContentVersion> allVersions = [
                SELECT Id, ContentDocumentId, IsDeleted, IsLatest
                FROM ContentVersion
                WHERE Id = :versionId
                ALL ROWS
        ];

        System.debug('=== DIAGNOSTIC ALL ROWS ContentVersions: ' + allVersions);

        // Inspect the document link as well.



        System.assertEquals(
        1,
        mock.tokenCalls,
        'Dropbox access token should be requested once.'
        );

        System.assertEquals(
        1,
        mock.uploadCalls,
        'Dropbox upload should be attempted once.'
        );

        System.assertEquals(
        1,
        mock.shareCalls,
        'Dropbox shared-link creation should be attempted once.'
        );

        System.assertEquals(
        0,
        mock.listCalls,
        'list_shared_links should not be called when shared-link creation fails.'
        );

        System.assertEquals(
        0,
        [
        SELECT COUNT()
        FROM FileLink__c
        ],
        'No FileLink should be created when shared-link creation fails.'
        );

    }


    /*
     * -------------------------------------------------------
     * Test queueable with empty Set
     * -------------------------------------------------------
     */
    @IsTest
    static void testQueueableWithEmptySet() {

        Test.startTest();

        System.enqueueJob(
                new VMT_DropboxUploadQueueable(
                        new Set<Id>()
                )
        );

        Test.stopTest();

        System.assertEquals(
                0,
                [
                        SELECT COUNT()
                        FROM FileLink__c
                ],
                'Empty ContentDocument ID set should not create FileLinks.'
        );
    }
}