trigger CapExApprovedTrigger on CapEx_Approved__e(after insert) {
    new CapExApprovedTriggerHandler().run();
}
