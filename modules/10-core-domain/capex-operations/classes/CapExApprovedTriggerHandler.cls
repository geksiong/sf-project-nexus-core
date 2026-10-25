/**
 * @description Platform event consumer for CapEx_Approved__e. Runs as the Automated Process user, in its
 * own transaction after the approval commits (ADR 0002).
 */
public with sharing class CapExApprovedTriggerHandler extends TriggerHandler {
    protected override void afterInsert(List<SObject> newRecords, Map<Id, SObject> newRecordMap) {
        LedgerPostingService.recordApprovals((List<CapEx_Approved__e>) newRecords);
    }
}
