/**
 * Created by Angine on 23/09/2026.
 */

@IsTest
private class VMT_DropboxTokenServiceTest {

    /**
     * Mock used by the token service.
     */
    private class DropboxTokenMock implements HttpCalloutMock {

        private Integer statusCode;
        private String responseBody;

        DropboxTokenMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {

            System.assertEquals(
                    'POST',
                    req.getMethod(),
                    'Dropbox token endpoint must use POST.'
            );

            System.assertEquals(
                    'https://api.dropboxapi.com/oauth2/token',
                    req.getEndpoint(),
                    'Unexpected Dropbox token endpoint.'
            );

            System.assertEquals(
                    'application/x-www-form-urlencoded',
                    req.getHeader('Content-Type')
            );

            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);

            return res;
        }
    }


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


    @IsTest
    static void testGetAccessTokenSuccess() {

        createDropboxSettings();

        Test.setMock(
                HttpCalloutMock.class,
                new DropboxTokenMock(
                        200,
                        '{"access_token":"test-access-token","expires_in":3600}'
                )
        );

        Test.startTest();

        String token =
                VMT_DropboxTokenService.getAccessToken();

        Test.stopTest();

        System.assertEquals(
                'test-access-token',
                token,
                'The access token returned by Dropbox should be returned.'
        );
    }


    @IsTest
    static void testGetAccessTokenFailure() {

        createDropboxSettings();

        Test.setMock(
                HttpCalloutMock.class,
                new DropboxTokenMock(
                        400,
                        '{"error":"invalid_grant"}'
                )
        );

        Test.startTest();

        Boolean exceptionThrown = false;

        try {

            VMT_DropboxTokenService.getAccessToken();

        } catch (CalloutException ex) {

            exceptionThrown = true;

            System.assert(
                    ex.getMessage().contains(
                            'Dropbox token refresh failed'
                    ),
                    'Exception should identify the Dropbox token failure.'
            );
        }

        Test.stopTest();

        System.assertEquals(
                true,
                exceptionThrown,
                'A failed Dropbox token request must throw CalloutException.'
        );
    }


    @IsTest
    static void testAccessTokenIsCached() {

        createDropboxSettings();

        Test.setMock(
                HttpCalloutMock.class,
                new DropboxTokenMock(
                        200,
                        '{"access_token":"cached-token","expires_in":3600}'
                )
        );

        Test.startTest();

        String firstToken =
                VMT_DropboxTokenService.getAccessToken();

        String secondToken =
                VMT_DropboxTokenService.getAccessToken();

        Test.stopTest();

        System.assertEquals(
                'cached-token',
                firstToken
        );

        System.assertEquals(
                'cached-token',
                secondToken,
                'The second call should use the cached access token.'
        );
    }
}