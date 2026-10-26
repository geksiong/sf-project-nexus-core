trigger DealRegistrationTrigger on Deal_Registration__c(before insert, before update, after insert) {
    new DealRegistrationTriggerHandler().run();
}
