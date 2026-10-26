trigger SuiteBookingTrigger on Suite_Booking__c(before insert, before update) {
    new SuiteBookingTriggerHandler().run();
}
