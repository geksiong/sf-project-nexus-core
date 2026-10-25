public with sharing class CaseTriggerHandler extends TriggerHandler {
    protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        // Enforce state transitions or SLA escalation checks
    }
}