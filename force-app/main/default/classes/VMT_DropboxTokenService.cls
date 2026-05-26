/**
 * Created by Angine on 25/05/2026.
 */

public class VMT_DropboxTokenService {

    public static final String CLIENT_ID = DropboxSettings__c.getOrgDefaults().ClientId__c;
    public static final String CLIENT_SECRET = DropboxSettings__c.getOrgDefaults().ClientSecret__c;
    final static String refreshToken =
            DropboxSettings__c.getOrgDefaults().RefreshToken__c;

    private static String accessToken;
    private static Long expiresAt;


    public static String getAccessToken() {
        if (accessToken != null && System.now().getTime() < expiresAt) {
            return accessToken;
        }

        refreshAccessToken();
        return accessToken;
    }

    private static void refreshAccessToken() {


        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.dropboxapi.com/oauth2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        req.setBody(
                'grant_type=refresh_token'
                        + '&refresh_token=' + refreshToken
                        + '&client_id=' + CLIENT_ID
                        + '&client_secret=' + CLIENT_SECRET
        );

        System.debug('im here: request : ' + req.getBody());

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new CalloutException('Dropbox token refresh failed: ' + res.getBody());
        }

        Map<String, Object> data =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        accessToken = (String) data.get('access_token');

        Integer expiresIn = (Integer) data.get('expires_in');
        expiresAt = System.now().getTime() + (expiresIn * 1000);
    }
}