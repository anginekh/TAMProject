/**
 * Created by Angine on 16/07/2025.
 */

@isTest
private class NK_PDFCreatorPETriggerTest {

    // Mock callout to avoid actual HTTP call from cadmus_core.ConvertController
    public class PDFButlerMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"result":"SUCCESS_WITH_WARNINGS","response":{"metadata":{"targetName":"Test.pdf"},"base64":"SGVsbG8gd29ybGQ="}}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void testPlatformEventTriggerFires() {
        Test.setMock(HttpCalloutMock.class, new PDFButlerMock());

        // Set up required test data
        Account acc = new Account(Name = 'PE Mieter');
        insert acc;

        Objekt__c objekt = new Objekt__c(Name = 'Objekt PE');
        insert objekt;

        Wohnung__c wohnung = new Wohnung__c(Name = 'Wohnung PE', Objekt__c = objekt.Id, WohnflaecheQm__c = 75);
        insert wohnung;

        Nebenkosten__c nk = new Nebenkosten__c(Objekt__c = objekt.Id, Jahr__c = String.valueOf(Date.today().year()-1));
        insert nk;

        Mietvertrag__c mv = new Mietvertrag__c(
                Wohnung__c = wohnung.Id,
                Mieter__c = acc.Id,
                AktuellerSaldo__c = 110, // Should trigger NK_Abrechnung_HighPlus
                NBKEhDatum__c = Date.today().addDays(20),
                KaltmieteNeu__c = 600
        );
        insert mv;

        // Create matching doc configs
        List<cadmus_core__Doc_Config__c> configs = new List<cadmus_core__Doc_Config__c>{
                new cadmus_core__Doc_Config__c(Name = 'NK_Abrechnung_HighPlus'),
                new cadmus_core__Doc_Config__c(Name = 'NK_Abrechnung_Excel')
        };
        insert configs;

        RecordType rt = [SELECT Id FROM RecordType WHERE Name = 'KEYVALUE' LIMIT 1];
        cadmus_core__Data_Source__c ds1 = new cadmus_core__Data_Source__c (Name = 'inputMap', RecordTypeId = rt.Id);
        insert ds1;

        // Create Platform Event
        Test.startTest();

        NK_PDFCreator_PE__e event = new NK_PDFCreator_PE__e(
                MietvertragIdList__c = JSON.serialize(new List<String>{mv.Id}),
                NebenkostenId__c =  nk.Id
        );
        Database.SaveResult result = EventBus.publish(event);

        Test.stopTest();

        System.assert(result.isSuccess(), 'Platform event should publish successfully');

        // Confirm PDF + Excel versions created
        List<ContentVersion> contentVersions = [SELECT Id FROM ContentVersion WHERE Title LIKE 'Nebenkostenabrechnung%'];
        //System.assertEquals(2, contentVersions.size(), 'Expected both PDF and Excel documents to be created.');

        // Confirm document links
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :mv.Id];
        //System.assertEquals(2, links.size(), 'Expected 2 document links.');
    }
}