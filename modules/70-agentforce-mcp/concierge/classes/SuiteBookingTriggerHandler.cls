public with sharing class SuiteBookingTriggerHandler extends TriggerHandler {
    protected override void beforeInsert(List<SObject> newRecords) {
        HotelConciergeService.applyBookingRules((List<Suite_Booking__c>) newRecords, null);
    }

    protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        HotelConciergeService.applyBookingRules(
            (List<Suite_Booking__c>) updatedRecords,
            (Map<Id, Suite_Booking__c>) oldRecordMap
        );
    }
}
