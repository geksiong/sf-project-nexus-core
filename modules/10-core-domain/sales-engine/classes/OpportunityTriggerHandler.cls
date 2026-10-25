public with sharing class OpportunityTriggerHandler extends TriggerHandler {
    protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        OpportunityService.validateStageProgression((List<Opportunity>) updatedRecords, (Map<Id, Opportunity>) oldRecordMap);
    }
}