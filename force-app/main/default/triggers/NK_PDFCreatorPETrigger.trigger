/**
 * Platform Event Trigger called from "UpdateNebenkostenAndSaldoOnMietvertrag" Flow
 * 
 *
 * @author  Angineh Khashaki
 * @date    27.04.2025
 * 
 */
trigger NK_PDFCreatorPETrigger on NK_PDFCreator_PE__e (after insert) {

    List <String> MietvertragIdList;
    for (NK_PDFCreator_PE__e event : trigger.new) {
        System.debug('Payload received: ' + Event.MietvertragIdList__c);
        MietvertragIdList = (List<String>) JSON.deserialize(Event.MietvertragIdList__c, List<String>.class);
        System.debug('im here ' +MietvertragIdList);
        String NebenkostenId = Event.NebenkostenId__c;
        NK_PDFCreator.createPDF(MietvertragIdList, NebenkostenId);
    }

}