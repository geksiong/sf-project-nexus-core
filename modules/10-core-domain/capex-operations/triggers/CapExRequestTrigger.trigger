trigger CapExRequestTrigger on CapEx_Request__c(before insert, before update, after update) {
    new CapExRequestTriggerHandler().run();
}
