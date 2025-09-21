/**
 * Created by Angine on 21/09/2025.
 */

global class CaseWiedervorlageScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new CaseWiedervorlageBatch(), 200);
    }
}
