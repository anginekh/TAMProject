/**
 * Created by Angine on 20/07/2025.
 */

global class NebenkostenActionable_ObjektAndLastYear implements cadmus_core.AbstractBeforeActionable {
    global void execute(cadmus_core__Actionable__c actionable,
            Id docConfig,
            Id objectId,
            Map<String, Object> inputMap,
            cadmus_core.ConvertController.ConvertDataModel cdm) {
        //the part below will add a variable that can be used in a SOQL to filter
        Mietvertrag__c mv = [SELECT Id, Wohnung__r.Objekt__c, Mieter__r.Name FROM Mietvertrag__c WHERE Id =:objectId];
        System.debug('im here mv : '+ mv);
        inputMap.put('ObjektId', mv.Wohnung__r.Objekt__c);
        inputMap.put('LastYear', String.valueOf(Date.today().year()-1));
        System.debug('im here inputMap : '+ inputMap);
    }
}