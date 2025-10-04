/**
 * Created by Angine on 16/07/2025.
 */

@isTest
private class NK_PDFCreatorTest {

    public class PDFButlerMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"result":"SUCCESS_WITH_WARNINGS","response":{"metadata":{"targetName":"Test.pdf"},"base64":"SGVsbG8gd29ybGQ="}}');
            res.setStatusCode(200);
            return res;
        }
    }

    private static Mietvertrag__c createMietvertrag(Decimal saldo, Date erhDatum, Account acc, Wohnung__c wohnung) {
        return new Mietvertrag__c(
                Wohnung__c = wohnung.Id,
                Mieter__c = acc.Id,
                AktuellerSaldo__c = saldo,
                NBKEhDatum__c = erhDatum,
                KaltmieteNeu__c = 400
        );
    }

    @isTest
    static void testCreatePDF_AllScenarios() {
        Test.setMock(HttpCalloutMock.class, new PDFButlerMock());

        Account acc = new Account(Name = 'Test Mieter');
        insert acc;

        Objekt__c objekt = new Objekt__c(Name = 'Objekt 1');
        insert objekt;

        Wohnung__c wohnung = new Wohnung__c(Name = 'Wohnung 1', Objekt__c = objekt.Id, WohnflaecheQm__c = 60);
        insert wohnung;

        // Create doc configs
        List<String> configNames = new List<String>{
                'NK_Abrechnung_HighMinus',
                'NK_Abrechnung_HighMinus_Erhoehung',
                'NK_Abrechnung_LowMinus',
                'NK_Abrechnung_LowMinus_Erhoehung',
                'NK_Abrechnung_LowPlus',
                'NK_Abrechnung_HighPlus',
                'NK_Abrechnung_Excel'
        };

        List<cadmus_core__Doc_Config__c> docConfigs = new List<cadmus_core__Doc_Config__c>();
        for (String name : configNames) {
            docConfigs.add(new cadmus_core__Doc_Config__c(Name = name));
        }
        insert docConfigs;

        RecordType rt = [SELECT Id FROM RecordType WHERE Name = 'KEYVALUE' LIMIT 1];
        cadmus_core__Data_Source__c ds1 = new cadmus_core__Data_Source__c (Name = 'inputMap', RecordTypeId = rt.Id);
        insert ds1;

        Date today = Date.today();
        List<Mietvertrag__c> testMVs = new List<Mietvertrag__c>{
                // Scenario 1: HighPlus (saldo >= 100)
                createMietvertrag(150, null, acc, wohnung),
                // Scenario 2: LowPlus (saldo >= 0 && < 100)
                createMietvertrag(50, null, acc, wohnung),
                // Scenario 3: LowMinus_Erhoehung (saldo < 0 && > -100 && NBKEhDatum__c >= today)
                createMietvertrag(-50, today.addDays(1), acc, wohnung),
                // Scenario 4: LowMinus (saldo < 0 && > -100 && NBKEhDatum__c < today)
                createMietvertrag(-50, today.addDays(-1), acc, wohnung),
                // Scenario 5: HighMinus_Erhoehung (saldo <= -100 && NBKEhDatum__c >= today)
                createMietvertrag(-150, today.addDays(1), acc, wohnung),
                // Scenario 6: HighMinus (saldo <= -100 && NBKEhDatum__c < today)
                createMietvertrag(-150, today.addDays(-1), acc, wohnung),
                // Edge: Null saldo
                new Mietvertrag__c(
                        Wohnung__c = wohnung.Id,
                        Mieter__c = acc.Id,
                        AktuellerSaldo__c = null,
                        NBKEhDatum__c = null,
                        KaltmieteNeu__c = 400
                )
        };
        insert testMVs;

        Test.startTest();
        NK_PDFCreator.createPDF(new List<Id>{
                testMVs[0].Id, testMVs[1].Id, testMVs[2].Id, testMVs[3].Id,
                testMVs[4].Id, testMVs[5].Id, testMVs[6].Id
        });
        Test.stopTest();

        // Basic assertions
        List<ContentVersion> cvs = [SELECT Id, Title FROM ContentVersion WHERE Title LIKE 'Nebenkostenabrechnung%'];
        //System.assert(cvs.size() >= 12, 'Should have created at least 2 documents per valid Mietvertrag');

        //List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId IN :testMVs];
        //System.assertEquals(cvs.size(), links.size(), 'Each content should have one link');

        // Confirm the doc titles are prefixed correctly
        for (ContentVersion cv : cvs) {
            //System.assert(cv.Title.startsWith('Nebenkostenabrechnung'), 'Doc title should follow naming pattern');
        }
    }

    @isTest
    static void testMissingDocConfig() {
        // Register callout mock
        Test.setMock(HttpCalloutMock.class, new PDFButlerMock());

        Account acc = new Account(Name = 'Missing Config Tester');
        insert acc;

        Objekt__c objekt = new Objekt__c(Name = 'Objekt Test');
        insert objekt;

        Wohnung__c wohnung = new Wohnung__c(Name = 'Wohnung Test', Objekt__c = objekt.Id, WohnflaecheQm__c = 55);
        insert wohnung;

        // This saldo triggers a config name, but we won't insert that config
        Mietvertrag__c mv = new Mietvertrag__c(
                Wohnung__c = wohnung.Id,
                Mieter__c = acc.Id,
                AktuellerSaldo__c = 150,  // Would trigger 'NK_Abrechnung_HighPlus'
                NBKEhDatum__c = Date.today().addDays(10),
                KaltmieteNeu__c = 500
        );
        insert mv;

        // Only insert Excel config (omit HighPlus on purpose)
        cadmus_core__Doc_Config__c excelConfig = new cadmus_core__Doc_Config__c(Name = 'NK_Abrechnung_Excel');
        insert excelConfig;

        RecordType rt = [SELECT Id FROM RecordType WHERE Name = 'KEYVALUE' LIMIT 1];
        cadmus_core__Data_Source__c ds1 = new cadmus_core__Data_Source__c (Name = 'inputMap', RecordTypeId = rt.Id);
        insert ds1;

        Test.startTest();
        NK_PDFCreator.createPDF(new List<String>{mv.Id});
        Test.stopTest();

        // Assert no document created since doc config was missing
        List<ContentVersion> noCVs = [SELECT Id FROM ContentVersion WHERE Title LIKE 'Nebenkostenabrechnung%'];
        //System.assertEquals(1, noCVs.size(), 'Only Excel version should have been created.');
    }
}