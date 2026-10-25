@IsTest
private class SalesEngineSelectorsTest {
    @IsTest
    static void emptyInputsShortCircuitWithoutQuerying() {
        SalesEngineFactsSelector facts = SalesEngineFactsSelector.newInstance();
        Assert.isTrue(OpportunitiesSelector.newInstance().selectByIdWithDetails(new Set<Id>()).isEmpty());
        Assert.isTrue(OpportunitiesSelector.newInstance().selectByIdWithDetails(null).isEmpty());
        Assert.isTrue(facts.selectAccountIdsOnCreditHold(new Set<Id>()).isEmpty());
        Assert.isTrue(facts.selectAccountIdsOnCreditHold(null).isEmpty());
        Assert.isTrue(facts.selectOpportunityIdsWithPrimaryContact(new Set<Id>()).isEmpty());
        Assert.isTrue(facts.selectOpportunityIdsWithPrimaryContact(null).isEmpty());
        Assert.isTrue(facts.selectManagerChains(new Set<Id>()).isEmpty());
        Assert.isTrue(facts.selectManagerChains(null).isEmpty());
        Assert.areEqual(0, Limits.getQueries(), 'Empty inputs must not consume SOQL queries');
    }

    /** @description Facts ignore the running user's field access and sharing. */
    @IsTest
    static void factsAreVisibleToUsersWithoutSalesPermissions() {
        User outsider = TestDataFactory.createTestUser('Standard User', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert outsider;
        }
        List<Account> accounts = TestDataFactory.createAccounts(2, false);
        accounts[0].Credit_Hold__c = true;
        insert accounts;
        Opportunity opp = TestDataFactory.createOpportunities(accounts[0].Id, 1, true)[0];
        Contact contact = TestDataFactory.createContacts(accounts[0].Id, 1, true)[0];
        insert new OpportunityContactRole(OpportunityId = opp.Id, ContactId = contact.Id, IsPrimary = true);

        System.runAs(outsider) {
            SalesEngineFactsSelector facts = new SalesEngineFactsSelector();
            Assert.areEqual(
                new Set<Id>{ accounts[0].Id },
                facts.selectAccountIdsOnCreditHold(new Map<Id, Account>(accounts).keySet())
            );
            Assert.areEqual(
                new Set<Id>{ opp.Id },
                facts.selectOpportunityIdsWithPrimaryContact(new Set<Id>{ opp.Id }),
                'Primary contact roles are found regardless of the running user\'s access'
            );
            Assert.isTrue(facts.selectManagerChains(new Set<Id>{ UserInfo.getUserId() }).containsKey(outsider.Id));
        }
    }
}
