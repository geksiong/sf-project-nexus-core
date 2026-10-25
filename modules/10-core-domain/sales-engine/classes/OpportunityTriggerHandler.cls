public with sharing class OpportunityTriggerHandler extends TriggerHandler {
    protected override void beforeInsert(List<SObject> newRecords) {
        OpportunityService.applyDiscountApprovalPolicy((List<Opportunity>) newRecords, null);
        OpportunityService.validateStageProgression((List<Opportunity>) newRecords, null);
    }

    protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        OpportunityService.applyDiscountApprovalPolicy(
            (List<Opportunity>) updatedRecords,
            (Map<Id, Opportunity>) oldRecordMap
        );
        OpportunityService.validateStageProgression(
            (List<Opportunity>) updatedRecords,
            (Map<Id, Opportunity>) oldRecordMap
        );
    }
}
