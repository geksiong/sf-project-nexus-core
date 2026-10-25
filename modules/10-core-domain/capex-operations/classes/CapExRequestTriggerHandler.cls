public with sharing class CapExRequestTriggerHandler extends TriggerHandler {
    protected override void beforeInsert(List<SObject> newRecords) {
        CapExService.validateRequests((List<CapEx_Request__c>) newRecords, null);
    }

    protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        List<CapEx_Request__c> requests = (List<CapEx_Request__c>) updatedRecords;
        Map<Id, CapEx_Request__c> oldMap = (Map<Id, CapEx_Request__c>) oldRecordMap;
        CapExService.validateRequests(requests, oldMap);
        CapExService.markApprovedForPosting(requests, oldMap);
    }

    protected override void afterUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        CapExService.publishApprovals(
            (List<CapEx_Request__c>) updatedRecords,
            (Map<Id, CapEx_Request__c>) oldRecordMap
        );
    }
}
