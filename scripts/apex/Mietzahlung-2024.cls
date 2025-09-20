/**
 * Created by Angine on 05/07/2025.
 */

List<Mietvertrag__c> mietvertrags = [SELECT Id, Mieter__c, Objekt__c FROM Mietvertrag__c WHERE Firma__c != 'ALG Grundbesitz GmbH' and IsFlat__c = TRUE];
List <Mietzahlung__c> mietzahlungList = new List <Mietzahlung__c>();
for (mietvertrag__c m:mietvertrags){
    Mietzahlung__c mit = new Mietzahlung__c (
            Mieter__c= m.Mieter__c,
            Mietvertrag__c = m.Id,
            Jahr__c = '2024',
            Objekt__c = m.Objekt__c,
            Bemerkungen__c = 'Diese Mietzahlung wurde einmalig automatisch erstellt, deshalb nur "Nebenkosten Bezahlt 2024" ausgefüllt.'
    );
    mietzahlungList.add(mit);
}
insert mietzahlunglist;

