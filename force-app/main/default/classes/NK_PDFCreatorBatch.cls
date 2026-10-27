/**
 * Generates Nebenkosten PDF + Excel one Mietvertrag at a time so PDF Butler
 * (cadmus_core) does not hit the async SOQL governor limit.
 */
public with sharing class NK_PDFCreatorBatch implements Database.Batchable<String>, Database.AllowsCallouts {

    public static final Integer BATCH_SIZE = 1;

    private List<String> mietvertragIds;
    private String nebenkostenId;

    public NK_PDFCreatorBatch(List<String> mietvertragIds, String nebenkostenId) {
        this.mietvertragIds = mietvertragIds != null ? mietvertragIds : new List<String>();
        this.nebenkostenId = nebenkostenId;
    }

    public static Id run(List<String> mietvertragIds, String nebenkostenId) {
        if (mietvertragIds == null || mietvertragIds.isEmpty() || String.isBlank(nebenkostenId)) {
            return null;
        }
        return Database.executeBatch(new NK_PDFCreatorBatch(mietvertragIds, nebenkostenId), BATCH_SIZE);
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        return mietvertragIds;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        if (scope == null || scope.isEmpty() || String.isBlank(nebenkostenId)) {
            return;
        }
        NK_PDFCreator.createPDF(scope, nebenkostenId);
    }

    public void finish(Database.BatchableContext bc) {
    }
}