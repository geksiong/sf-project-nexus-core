public with sharing class DealRegistrationTriggerHandler extends TriggerHandler {
    protected override void beforeInsert(List<SObject> newRecords) {
        DealRegistrationService.prepareRegistrations((List<Deal_Registration__c>) newRecords);
    }

    protected override void afterInsert(List<SObject> newRecords, Map<Id, SObject> newRecordMap) {
        DealRegistrationService.submitForApproval((List<Deal_Registration__c>) newRecords);
    }

    protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        DealRegistrationService.convertApproved(
            (List<Deal_Registration__c>) updatedRecords,
            (Map<Id, Deal_Registration__c>) oldRecordMap
        );
    }
}
