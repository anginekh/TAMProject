/**
 * Contains the main logic to create and send the email with attachment for "Service form for replacement process"
 *
 * @author  Angineh Schulz
 * @date    27.04.2025
 */
public with sharing class NK_PDFCreator{

    @future(callout=true)
    public static void createPDF(List<String> MietvertragIdList){

        Boolean documentCreationFailed = false;
        //generate PDF document
        cadmus_core.ConvertController.ConvertDataModel cdm = new cadmus_core.ConvertController.ConvertDataModel();
        cadmus_core.DocGenerationWrapper result;

        cadmus_core.ConvertController.ConvertDataModel cdm2 = new cadmus_core.ConvertController.ConvertDataModel();
        cadmus_core.DocGenerationWrapper result2;

        /*Map<String, cadmus_core__Pack__c> packMap = new Map<String, cadmus_core__Pack__c>();
        List <cadmus_core__Pack__c> packs = (List <cadmus_core__Pack__c>) [SELECT Id, Name FROM cadmus_core__Pack__c WHERE Name LIKE 'NK_Abrechnung%'];
        System.debug('im here 0 : ' + packs);
        for(cadmus_core__Pack__c p:packs){
            packMap.put(p.Name, p);
        }*/

        List <Mietvertrag__c> mietvertragList = [SELECT Id, AktuellerSaldo__c, NBKEhDatum__c FROM Mietvertrag__c WHERE Id IN : MietvertragIdList];
        // Set your variable (name must match variable used in your PDF Butler template)
        Mietvertrag__c mv = [SELECT Id, Wohnung__r.Objekt__c, Mieter__r.Name FROM Mietvertrag__c WHERE Id =: mietvertragList[0].Id];
        //cdm.inputMap = new Map<String, String>();
        //cdm.inputMap.put('ObjektId', mv.Wohnung__r.Objekt__c);
        //cdm.inputMap.put('LastYear', String.valueOf(Date.today().year()-1));

        Map <Id, ContentVersion> mietvertragIdCVMap1 = new Map <Id, ContentVersion> ();
        Map <Id, ContentVersion> mietvertragIdCVMap2 = new Map <Id, ContentVersion> ();
        for (Mietvertrag__c m:mietvertragList){
            //String packName;
            String docConfigName;
            if (m.AktuellerSaldo__c != null){
                //scenario 1
                if (m.AktuellerSaldo__c >= 100){
                    System.debug('im here 1 : ' + m.AktuellerSaldo__c);
                    //packName = 'NK_Abrechnung_HighPlus_Pack';
                    docConfigName = 'NK_Abrechnung_HighPlus';
                    //scenario 2
                }else if(m.AktuellerSaldo__c >= 0 && m.AktuellerSaldo__c < 100){
                    System.debug('im here 2 : ' + m.AktuellerSaldo__c);
                    //packName = 'NK_Abrechnung_LowPlus_Pack';
                    docConfigName = 'NK_Abrechnung_LowPlus';

                    //scenario 3,4
                }else if(m.AktuellerSaldo__c < 0 && m.AktuellerSaldo__c > -100){
                    //scenario 3
                    if(m.NBKEhDatum__c != null && m.NBKEhDatum__c >= System.today()){
                        System.debug('im here 3 : ' + m.AktuellerSaldo__c);
                        //packName = 'NK_Abrechnung_LowMinus_Erhoehung_Pack';
                        docConfigName = 'NK_Abrechnung_LowMinus_Erhoehung';
                        //scenario 4
                    }else if(m.NBKEhDatum__c == null || m.NBKEhDatum__c < System.today()){
                        System.debug('im here 4 : ' + m.AktuellerSaldo__c);
                        //packName = 'NK_Abrechnung_LowMinus_Pack';
                        docConfigName = 'NK_Abrechnung_LowMinus';
                    }
                    //scenario 5,6
                }else if(m.AktuellerSaldo__c <= -100){
                    //scenario 5
                    if(m.NBKEhDatum__c != null && m.NBKEhDatum__c >= System.today()){
                        System.debug('im here 5 : ' + m.AktuellerSaldo__c);
                        //packName = 'NK_Abrechnung_HighMinus_Erhoehung_Pack';
                        docConfigName = 'NK_Abrechnung_HighMinus_Erhoehung';
                        //scenario 6
                    }else if(m.NBKEhDatum__c == null || m.NBKEhDatum__c < System.today()){
                        System.debug('im here 6 : ' + m.AktuellerSaldo__c);
                        //packName = 'NK_Abrechnung_HighMinus_Pack';
                        docConfigName = 'NK_Abrechnung_HighMinus';
                    }
                }

            }else{
                //register the error that Mietvertrag's AktuellerSaldo__c is empty.
            }

            Map<String, cadmus_core__Doc_Config__c> docConfigMap = new Map<String, cadmus_core__Doc_Config__c>();
            List <cadmus_core__Doc_Config__c> docConfigs = (List <cadmus_core__Doc_Config__c>) [SELECT Id, Name FROM cadmus_core__Doc_Config__c WHERE Name LIKE 'NK_Abrechnung%'];
            System.debug('im here 0 : ' + docConfigs);
            for (cadmus_core__Doc_Config__c d : docConfigs) {
                docConfigMap.put(d.Name, d);
            }
            if (docConfigMap.containsKey(docConfigName) && docConfigMap.get(docConfigName) != null) {
                cdm.docConfigId = docConfigMap.get(docConfigName).Id;
                cdm.objectId = m.Id;

                // Call PDF Butler
                if (Test.isRunningTest()) {
                    result = null;
                } else { result = cadmus_core.ConvertController.convertWithWrapper(cdm);
                }
                if (result == null || result.result == 'FAILED') {
                    documentCreationFailed = true;
                    System.debug('im here 8 : error');
                } else {
                    System.debug('im here 9: success - doc target name: ' + result.response.metadata.targetName + ' doc base64: ' + result.response.base64);

                    ContentVersion cv = new ContentVersion();
                    cv.Title = 'Nebenkostenabrechnung_'+ String.valueOf(System.today().year() - 1) +'_'+ mv.Mieter__r.Name;
                    cv.PathOnClient = result.response.metadata.targetName;
                    cv.VersionData = result.response.base64;
                    cv.Origin = 'H';
                    mietvertragIdCVMap1.put(m.Id,cv);
                    System.debug('in here 10 : mietvertragIdCVMap1 ' + mietvertragIdCVMap1);

                    System.debug('im here 11 : generating the excel document');
                    // generate Excel version
                    cdm2.docConfigId = docConfigMap.get('NK_Abrechnung_Excel').Id;
                    cdm2.objectId = m.Id;
                    result2 = cadmus_core.ConvertController.convertWithWrapper(cdm2);
                    if (result2 == null || result.result == 'FAILED') { documentCreationFailed = true;
                        System.debug('im here 8 : error');
                    } else {
                        System.debug('im here 9: success - doc target name: ' + result2.response.metadata.targetName + ' doc base64: ' + result2.response.base64);
                        ContentVersion cv2 = new ContentVersion();
                        cv2.Title = 'Nebenkostenabrechnung_Excel_'+ String.valueOf(System.today().year() - 1) + '_' + mv.Mieter__r.Name;
                        cv2.PathOnClient = result2.response.metadata.targetName;
                        cv2.VersionData = result2.response.base64;
                        cv2.Origin = 'H';
                        mietvertragIdCVMap2.put(m.Id,cv2);
                        System.debug('in here 10 : mietvertragIdCVMap2 ' + mietvertragIdCVMap2);


                    }
                }
            } else {
                System.debug('im here 12 no doc config with the name : ' + docConfigName + ' found.');
                //register an error
            }
        }
        System.debug('im here 13: mietvertragIdCVMap1 ' + mietvertragIdCVMap1);
        System.debug('im here 14: mietvertragIdCVMap2 ' + mietvertragIdCVMap2);

        insert mietvertragIdCVMap1.values();
        insert mietvertragIdCVMap2.values();

        List<ContentDocumentLink> contentDocumentLinks = new List<ContentDocumentLink>();
        Map<Id, ContentVersion> ContentVersionMap1= new Map <Id, ContentVersion> ([SELECT Id, ContentDocumentID FROM ContentVersion WHERE Id IN: mietvertragIdCVMap1.values()]);
        Map <Id, Id> mietvertragIdCVDocumentIdMap1 = new map <Id, Id> ();
        for (Id mvId:mietvertragIdCVMap1.keyset()){ mietvertragIdCVDocumentIdMap1.put(mvId,ContentVersionMap1.get(mietvertragIdCVMap1.get(mvId).Id).ContentDocumentID);
        }

        System.debug('im here 15 mietvertragIdCVDocumentIdMap1 '+ mietvertragIdCVDocumentIdMap1);

        Map<Id, ContentVersion> ContentVersionMap2= new Map <Id, ContentVersion> ([SELECT Id, ContentDocumentID FROM ContentVersion WHERE Id IN: mietvertragIdCVMap2.values()]);
        Map <Id, Id> mietvertragIdCVDocumentIdMap2 = new map <Id, Id> ();
        for (Id mvId:mietvertragIdCVMap2.keyset()){ mietvertragIdCVDocumentIdMap2.put(mvId,ContentVersionMap2.get(mietvertragIdCVMap2.get(mvId).Id).ContentDocumentID);
        }

        System.debug('im here 16 mietvertragIdCVDocumentIdMap2 '+ mietvertragIdCVDocumentIdMap2);
        for (Id mvId:mietvertragIdCVMap1.keyset()){
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = mietvertragIdCVDocumentIdMap1.get(mvId);
            cdl.LinkedEntityId = mvId;
            cdl.Sharetype = 'V'; // view permission
            cdl.Visibility = 'AllUsers'; // AllUsers, InternalUsers, SharedUsers
            contentDocumentLinks.add(cdl);
        }

        for (Id mvId:mietvertragIdCVMap2.keyset()){
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = mietvertragIdCVDocumentIdMap2.get(mvId);
            cdl.LinkedEntityId = mvId;
            cdl.Sharetype = 'V'; // view permission
            cdl.Visibility = 'AllUsers'; // AllUsers, InternalUsers, SharedUsers
            contentDocumentLinks.add(cdl);
        }

        insert contentDocumentLinks;

    }

}