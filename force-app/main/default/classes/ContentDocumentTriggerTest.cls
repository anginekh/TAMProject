/**
 * Created by Angine on 23/09/2026.
 */

@IsTest
private class ContentDocumentTriggerTest {


    /*
     * -------------------------------------------------------
     * Dropbox Mock
     * -------------------------------------------------------
     */
    private class TriggerDropboxMock
            implements HttpCalloutMock {

        public Integer tokenCalls = 0;
        public Integer uploadCalls = 0;
        public Integer shareCalls = 0;


        public HttpResponse respond(HttpRequest req) {

            String endpoint =
                    req.getEndpoint();


            /*
             * Token request
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
                        '{"access_token":"trigger-test-token","expires_in":3600}'
                );

                return res;
            }


            /*
             * Upload request
             */
            if (
                    endpoint ==
                            'https://content.dropboxapi.com/2/files/upload'
            ) {

                uploadCalls++;

                HttpResponse res =
                        new HttpResponse();

                res.setStatusCode(200);

                res.setBody(
                        '{' +
                                '"name":"TriggerTest.txt",' +
                                '"path_lower":"/salesforcefiles_automatedupload/trigger-test.txt",' +
                                '"id":"id:trigger-test"' +
                                '}'
                );

                return res;
            }


            /*
             * Shared-link request
             */
            if (
                    endpoint ==
                            'https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'
            ) {

                shareCalls++;

                HttpResponse res =
                        new HttpResponse();

                res.setStatusCode(200);

                res.setBody(
                        '{' +
                                '"url":"https://www.dropbox.com/s/trigger/test-file",' +
                                '"name":"TriggerTest.txt",' +
                                '"path_lower":"/salesforcefiles_automatedupload/trigger-test.txt"' +
                                '}'
                );

                return res;
            }


            HttpResponse res =
                    new HttpResponse();

            res.setStatusCode(404);

            res.setBody(
                    '{"error":"unexpected_endpoint"}'
            );

            return res;
        }
    }


    /*
     * -------------------------------------------------------
     * Create Dropbox Settings
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
     * Test ContentDocument trigger
     * -------------------------------------------------------
     */
    @IsTest
    static void testContentDocumentTriggerEnqueuesQueueable() {

        createDropboxSettings();

        Account acc =
                new Account(
                        Name = 'Trigger Test Account'
                );

        insert acc;


        TriggerDropboxMock mock =
                new TriggerDropboxMock();

        Test.setMock(
                HttpCalloutMock.class,
                mock
        );


        Test.startTest();


        /*
         * Inserting ContentVersion creates a
         * ContentDocument.
         *
         * ContentDocumentTrigger fires after insert
         * and enqueues VMT_DropboxUploadQueueable.
         */
        ContentVersion cv =
                new ContentVersion(
                        Title = 'Trigger Test File',
                        PathOnClient = 'Trigger Test File.txt',
                        VersionData = Blob.valueOf(
                                'Trigger test content'
                        ),
                        FirstPublishLocationId = acc.Id
                );

        insert cv;


        Test.stopTest();


        /*
         * ---------------------------------------------------
         * Verify queueable was executed
         * ---------------------------------------------------
         */
        System.assertEquals(
                1,
                mock.tokenCalls,
                'Queueable should request a Dropbox access token.'
        );

        System.assertEquals(
                1,
                mock.uploadCalls,
                'Queueable should upload the Salesforce file.'
        );

        System.assertEquals(
                1,
                mock.shareCalls,
                'Queueable should create a Dropbox shared link.'
        );


        /*
         * ---------------------------------------------------
         * Verify FileLink was created
         * ---------------------------------------------------
         */
        List<FileLink__c> fileLinks = [
                SELECT Id,
                        DropboxLink__c,
                        DropboxPath__c,
                        Mieter__c
                FROM FileLink__c
        ];


        System.assertEquals(
                1,
                fileLinks.size(),
                'The trigger should ultimately result in one FileLink.'
        );


        FileLink__c fl =
                fileLinks[0];


        System.assertEquals(
                'https://www.dropbox.com/s/trigger/test-file',
                fl.DropboxLink__c
        );

        System.assertEquals(
                acc.Id,
                fl.Mieter__c
        );


        /*
         * ---------------------------------------------------
         * Verify ContentDocument was deleted
         * ---------------------------------------------------
         */
        System.assertEquals(
                0,
                [
                        SELECT COUNT()
                        FROM ContentDocument
                        WHERE Id = :cv.ContentDocumentId
                ],
                'The ContentDocument should be deleted after successful processing.'
        );
    }
}