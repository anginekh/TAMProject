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
        Mietvertrag__c mv = [SELECT Id, Wohnung__r.Objekt__c, Wohnung__r.Objekt__r.Objektnummer__c, Mieter__r.Name, Eingezogen__c, Ausgezogen__c FROM Mietvertrag__c WHERE Id =:objectId];


        Integer lastYear = Date.today().year()-1;
        inputMap.put('ObjektId', mv.Wohnung__r.Objekt__c);
        inputMap.put('NKJahr', String.valueOf(lastYear));
        String objektNummer = mv.Wohnung__r.Objekt__r.Objektnummer__c;
        inputMap.put('ObjektNummer', objektNummer);

        Date beginningOfYear = Date.newInstance(lastYear, 1, 1);
        Date endOfYear = Date.newInstance(lastYear, 12, 31);
        Date startDate = (mv.Eingezogen__c < beginningOfYear || mv.Eingezogen__c == null) ? beginningOfYear: mv.Eingezogen__c;
        Date endDate = (mv.Ausgezogen__c > endOfYear || mv.Ausgezogen__c == null) ? endOfYear: mv.Ausgezogen__c;
        inputMap.put('StartDate', startDate);
        inputMap.put('EndDate', endDate);

        //todo add the variables

        /*
        Gebuehren
        GesamtHeizkostenWohnung
        GesamtHeizkostenObjekt
        GesamtHeizkostenObjektHaelfte
        */

    }
}