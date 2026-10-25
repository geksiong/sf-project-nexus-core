public with sharing class CaseTriggerHandler extends TriggerHandler {
    protected override void beforeInsert(List<SObject> newRecords) {
        CaseSlaService.assignEntitlements((List<Case>) newRecords, null);
    }

    protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        CaseSlaService.assignEntitlements((List<Case>) updatedRecords, (Map<Id, Case>) oldRecordMap);
        CaseEscalationService.applyEscalationPolicy((List<Case>) updatedRecords, (Map<Id, Case>) oldRecordMap);
    }

    protected override void afterInsert(List<SObject> newRecords, Map<Id, SObject> newRecordMap) {
        CaseTeamService.provisionCaseTeams((List<Case>) newRecords, null);
    }

    protected override void afterUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        List<Case> cases = (List<Case>) updatedRecords;
        Map<Id, Case> oldMap = (Map<Id, Case>) oldRecordMap;
        CaseEscalationService.recordEscalations(cases, oldMap);
        CaseTeamService.provisionCaseTeams(cases, oldMap);
        CaseSlaService.completeMilestones(cases, oldMap);
    }
}
