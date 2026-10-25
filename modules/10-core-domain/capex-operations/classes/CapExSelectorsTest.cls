@IsTest
private class CapExSelectorsTest {
    @IsTest
    static void emptyInputsShortCircuitWithoutQuerying() {
        CapExFactsSelector facts = CapExFactsSelector.newInstance();
        Assert.isTrue(CapExRequestsSelector.newInstance().selectById(null).isEmpty());
        Assert.isTrue(facts.selectLedgerEntryIdsByKey(new Set<String>()).isEmpty());
        Assert.isTrue(facts.selectPendingEntries(null).isEmpty());
        Assert.isTrue(facts.selectFailedEntryIds(new Set<Id>()).isEmpty());
        Assert.isTrue(facts.selectApprovedRequests(null).isEmpty());
        Assert.areEqual(0, Limits.getQueries(), 'Empty inputs must not consume SOQL queries');
    }

    /** @description The consumer and job read ledger data whoever runs them (Automated Process user). */
    @IsTest
    static void factsIgnoreTheRunningUsersAccess() {
        User outsider = TestDataFactory.createTestUser('Standard User', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert outsider;
        }
        CapEx_Request__c request = CapExTestFixtures.newRequest(UserInfo.getUserId(), 50);
        insert request;
        Ledger_Entry__c pending = new Ledger_Entry__c(CapEx_Request__c = request.Id, Idempotency_Key__c = request.Id);
        insert pending;

        System.runAs(outsider) {
            CapExFactsSelector facts = new CapExFactsSelector();
            Assert.areEqual(pending.Id, facts.selectLedgerEntryIdsByKey(new Set<String>{ request.Id }).get(request.Id));
            Assert.areEqual(1, facts.selectPendingEntries(new Set<Id>{ pending.Id }).size());
            Assert.isTrue(facts.selectFailedEntryIds(new Set<Id>{ request.Id }).isEmpty());
        }
    }
}
