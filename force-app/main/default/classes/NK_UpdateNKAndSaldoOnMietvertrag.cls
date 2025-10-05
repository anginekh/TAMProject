/**
 * Created by Angine on 29/09/2025.
 */

public with sharing class NK_UpdateNKAndSaldoOnMietvertrag {

    @InvocableMethod
    public static void nk_UpdateNkAndSaldo(List <String> nkId) {

        //try {


            System.debug('im here: nkId ' + nkId);
            Nebenkosten__c nk = [
                    SELECT Id, Objekt__c, Jahr__c, BetriebskostenTotal__c, Allgemeinstrom__c, EntwaesserungNiederschlag__c,
                            Gebaudeversicherung__c, Grundsteuer__c, Haftpflicht__c, Kabel__c, Muellabfuhr__c,
                            Schornsteinfeger__c, Strassenreinigung_Winterdienst__c, Treppenhausreinigung__c, Wartung__c,
                            Wasserversorgung__c, NebenkostenabrechnungDurchgefuehrt__c
                    FROM Nebenkosten__c
                    WHERE Id IN :nkId
                    LIMIT 1
            ];
            List<Mietzahlung__c> allMietzahlungen = [
                    SELECT Id, Mietvertrag__c, Mietvertrag__r.Id, Mietvertrag__r.Wohnflaechenanteil__c, Mietvertrag__r.Eingezogen__c, Mietvertrag__r.Ausgezogen__c,
                            Mietvertrag__r.BetriebskostenNeu__c, Mietvertrag__r.HeizkostenNeu__c, Mietvertrag__r.Mieter__c,
                            Mieter__c, NebenkostenBezahlt__c, NebenkostenBezahlt2024__c, Objekt__c, Jahr__c, IsFlat__c,
                            NK_AnteilAllgemeinstrom__c, NK_AnteilEntwaesserungNiederschlag__c, NK_AnteilGebaudeversicherung__c,
                            NK_AnteilGrundsteuer__c, NK_AnteilHaftpflicht__c, NK_AnteilKabel__c, NK_AnteilMuellabfuhr__c,
                            NK_AnteilSchornsteinfeger__c, NK_AnteilStrassenreinigung_Winterdienst__c, NK_AnteilTreppenhausreinigung__c,
                            NK_AnteilWartung__c, NK_AnteilWasserversorgung__c
                    FROM Mietzahlung__c
                    WHERE Objekt__c = :nk.Objekt__c
                    AND Jahr__c = :nk.Jahr__c
                    AND IsFlat__c = TRUE
            ];

            // Collect Mietvertrag Ids and Mieter Ids
            Set<Id> mietvertragIds = new Set<Id>();
            Set<Id> mieterIds = new Set<Id>();
            for (Mietzahlung__c mz : allMietzahlungen) {
                if (mz.Mietvertrag__c != null) mietvertragIds.add(mz.Mietvertrag__c);
                if (mz.Mieter__c != null) mieterIds.add(mz.Mieter__c);
            }

            List<Mietvertrag__c> mietvertraege = new List<Mietvertrag__c>();
            if (!mietvertragIds.isEmpty()) {
                mietvertraege = [
                        SELECT Id, Wohnflaechenanteil__c, Eingezogen__c, Ausgezogen__c, BetriebskostenNeu__c, HeizkostenNeu__c,
                                Mieter__c, Mieter__r.OffeneGebuehren__c
                        FROM Mietvertrag__c
                        WHERE Id IN :mietvertragIds
                        AND IsFlat__c = true
                ];
            }
            List<Heizkosten__c> heizkosten = [
                    SELECT Id, Mietvertrag__c, GesamtheizkostenWohnung__c
                    FROM Heizkosten__c
                    WHERE Objekt__c = :nk.Objekt__c
                    AND Jahr__c = :nk.Jahr__c
            ];


            Map <Id, Account> MieterMap = new Map <Id, Account> ([SELECT Id, OffeneGebuehren__c FROM Account WHERE Id IN :mieterIds]);

            // Prepare lists for DML
            List<Mietvertrag__c> mietvertraegeToUpdate = new List<Mietvertrag__c>();
            List<Mietzahlung__c> mietzahlungenToUpdate = new List<Mietzahlung__c>();
            List<SaldoNebenkosten__c> saldoToInsert = new List<SaldoNebenkosten__c>();
            List<Gebuehr__c> gebuehrenToUpdate = new List<Gebuehr__c>();

            // Map Mietzahlungen by Mietvertrag to ease lookup
            Map<Id, Mietzahlung__c> mietzahlungenByMietvertrag = new Map<Id, Mietzahlung__c>();
            for (Mietzahlung__c mz : allMietzahlungen) {
                if (mz.Mietvertrag__c == null) continue;
                if (!mietzahlungenByMietvertrag.containsKey(mz.Mietvertrag__c)) mietzahlungenByMietvertrag.put(mz.Mietvertrag__c, mz);
            }

            // Map Heizkosten by Mietvertrag Id
            Map<Id, Heizkosten__c> heizkostenByMietvertrag = new Map<Id, Heizkosten__c>();
            for (Heizkosten__c hk : heizkosten) {
                if (hk.Mietvertrag__c == null) continue;
                if (!heizkostenByMietvertrag.containsKey(hk.Mietvertrag__c)) heizkostenByMietvertrag.put(hk.Mietvertrag__c, hk);
            }

            for (Mietvertrag__c mv : mietvertraege) {

                Decimal betriebskostenToPay;
                Decimal offeneGebuehren;

                Decimal totalBk = nk.BetriebskostenTotal__c;            // Nebenkosten total
                Decimal share = mv.Wohnflaechenanteil__c;             // Tenant’s % share
                Decimal currentBk = mv.BetriebskostenNeu__c;              // Current monthly BK

                // Step 1: compute the theoretical monthly share
                Decimal monthlyShare = (totalBk != null && share != null)
                        ? (totalBk * (share / 100)) / 12
                        : 0;

                // Step 2: if the new share is higher, round up to next multiple of 5
                Decimal result;
                if (monthlyShare > currentBk) {
                    Decimal remainder = Math.mod(Integer.valueOf(monthlyShare), 5);
                    if (remainder > 0) {
                        result = Integer.valueOf(monthlyShare) - remainder + 5;  // round UP to next 5
                    } else {
                        result = monthlyShare;                  // already a multiple of 5
                    }
                } else {
                    result = currentBk;                          // keep the old charge
                }

                mv.BetriebskostenNeu__c = result;

                // Dates for year boundaries
                Date yearStart = Date.newInstance(Integer.valueOf(nk.Jahr__c), 1, 1);
                Date nextYearStart = Date.newInstance(Integer.valueOf(nk.Jahr__c) + 1, 1, 1);

                // Tenant's monthly cost share
                Decimal monthlyWohnungBetriebskosten = (nk.BetriebskostenTotal__c * (mv.Wohnflaechenanteil__c / 100)) / 12;


                //Only for this year (2024), the field 'Nebenkosten bezahlt 2024' is used. From next year, the usual field 'Nebenkosten bezahlt' applies.
                Decimal nebenkostenBezahlt = nk.Jahr__c == '2024' ? mietzahlungenByMietvertrag.get(mv.Id).NebenkostenBezahlt2024__c : mietzahlungenByMietvertrag.get(mv.Id).NebenkostenBezahlt__c;

                if (mv.Eingezogen__c != null && mv.Eingezogen__c >= nextYearStart){
                    //todo: log an error (type : data inconsistency) for Holm and support to explain that this MV is connected to a MZ of a year (e.g. 2024) where the
                    //todo mv eingezogen is for the year after (e.g. 2025)
                    continue;
                }
                if (mv.Ausgezogen__c < mv.Eingezogen__c){
                    //todo: log an error (type : data inconsistency) for Holm and support to explain that this MV is connected to a MZ of a year (e.g. 2024) where the
                    //todo mv eingezogen is for the year after (e.g. 2025)
                    continue;
                }
                Integer monthsLivedThatYear;
                // CASE 1: Moved in during this year
                if (mv.Eingezogen__c != null && mv.Eingezogen__c > yearStart) {

                    // CASE 1a: Also moved out during the year
                    if (mv.Ausgezogen__c != null && mv.Ausgezogen__c > yearStart && mv.Ausgezogen__c < nextYearStart) {
                        monthsLivedThatYear = mv.Ausgezogen__c.month() - mv.Eingezogen__c.month() + 1;
                    }
                    // CASE 1b: Still there at year end
                    else {
                        monthsLivedThatYear = 12 - mv.Eingezogen__c.month() + 1;
                    }

                    // CASE 2: Did not move in this year but moved out during the year
                } else if (mv.Ausgezogen__c != null && mv.Ausgezogen__c > yearStart && mv.Ausgezogen__c < nextYearStart) {
                    monthsLivedThatYear = mv.Ausgezogen__c.month();

                    // CASE 3: Full-year occupancy
                } else {
                    monthsLivedThatYear = 12;
                }

                betriebskostenToPay = monthlyWohnungBetriebskosten * monthsLivedThatYear;
                offeneGebuehren = MieterMap.get(mv.Mieter__c).OffeneGebuehren__c;

                Decimal gesamtHeizkostenWohnung = heizkostenByMietvertrag.containsKey(mv.Id) ? heizkostenByMietvertrag.get(mv.Id).GesamtheizkostenWohnung__c : 0;
                Decimal oldHeizkosten = mv.HeizkostenNeu__c;

                // Step 1: monthly calculated heating cost
                Decimal newMonthlyHeizkosten = gesamtHeizkostenWohnung / monthsLivedThatYear;

                // Step 2: compare and possibly round
                Decimal newHeizkosten;
                if (newMonthlyHeizkosten > oldHeizkosten) {
                    Decimal remainder = Math.mod(Integer.valueOf(newMonthlyHeizkosten), 5);
                    if (remainder > 0) {
                        newHeizkosten = Integer.valueOf(newMonthlyHeizkosten) - remainder + 5; // round UP to next 5
                    } else {
                        newHeizkosten = newMonthlyHeizkosten;                 // already a multiple of 5
                    }
                } else {
                    newHeizkosten = oldHeizkosten;                      // keep current
                }

                mv.HeizkostenNeu__c = newHeizkosten;
                mietvertraegeToUpdate.add(mv);

                mietzahlungenByMietvertrag.get(mv.Id).NK_AnteilBetriebskostenTotal__c = betriebskostenToPay;
                mietzahlungenToUpdate.add(mietzahlungenByMietvertrag.get(mv.Id));

                Decimal saldo = nebenkostenBezahlt - gesamtHeizkostenWohnung - betriebskostenToPay - offeneGebuehren;

                saldoToInsert.add(new SaldoNebenkosten__c(Betrag__c = saldo, Mietvertrag__c = mv.Id,
                        Typ__c = 'Saldo', Jahr__c = nk.Jahr__c));


                //todo: if needed calculate all the anteil fields on mz strom, and then update mietzahlung

            }


            List <Gebuehr__c> gebuehrList = [SELECT Id, Zahlungsstatus__c FROM Gebuehr__c WHERE Account__c IN :mieterIds AND Zahlungsstatus__c = 'Offen'];
            for (Gebuehr__c g : gebuehrList) {
                g.Zahlungsstatus__c = 'Berechnet in NK-Saldo';
                gebuehrenToUpdate.add(g);
            }

            //try {

                //update BetriebskostenNeu__c and HeizkostenNeu__c on Mietvertrag (only if increased)
                update mietvertraegeToUpdate;
                nk.NebenkostenabrechnungDurchgefuehrt__c = true;
                update nk;
                insert saldoToInsert;
                update gebuehrenToUpdate;
                update mietzahlungenToUpdate;

                String serializedJsonIdList = JSON.serialize(mietvertragIds);
                System.debug ('im here: ' + mietvertragIds);
                NK_PDFCreator_PE__e event = new NK_PDFCreator_PE__e (MietvertragIdList__c = serializedJsonIdList, NebenkostenId__c = nk.Id );
                EventBus.publish(event);

            /*} catch (Exception e) {
                //todo: exception handling
                System.debug('im here: exception happened ' + e + ' ' + e.getMessage());
            }*/


        /*}catch (Exception e){
            //todo: exception handling
            System.debug('im here: exception happened ' + e + ' ' + e.getMessage());
        }*/
    }

}