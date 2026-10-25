trigger CompliantTrigger on Account(before insert) {
    new AccountTriggerHandler().run();
}
