@IsTest
private class ServiceDeskSelectorsTest {
    @IsTest
    static void emptyInputsShortCircuitWithoutQuerying() {
        ServiceDeskFactsSelector facts = ServiceDeskFactsSelector.newInstance();
        Assert.isTrue(CasesSelector.newInstance().selectById(new Set<Id>()).isEmpty());
        Assert.isTrue(CasesSelector.newInstance().selectById(null).isEmpty());
        Assert.isTrue(facts.selectCaseTeamRoleIds(new Set<String>()).isEmpty());
        Assert.isTrue(facts.selectCaseTeamMemberKeys(null).isEmpty());
        Assert.isTrue(facts.selectActiveAccountOwnerIds(null).isEmpty());
        Assert.isTrue(facts.selectActiveUserIds(new Set<Id>()).isEmpty());
        Assert.isTrue(facts.selectActiveEntitlementIdsByAccount(null).isEmpty());
        Assert.isTrue(facts.selectOpenMilestoneIds(new Set<Id>()).isEmpty());
        Assert.areEqual(0, Limits.getQueries(), 'Empty inputs must not consume SOQL queries');
    }

    /** @description Facts ignore the running user's object access, field access and sharing. */
    @IsTest
    static void factsAreVisibleToUsersWithoutServicePermissions() {
        User outsider = TestDataFactory.createTestUser('Standard User', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert outsider;
            ServiceDeskTestFixtures.ensureCaseTeamRoles();
        }
        Account acc = TestDataFactory.createAccounts(1, true)[0];
        Entitlement ent = ServiceDeskTestFixtures.createEntitlement(acc.Id);
        Case c = ServiceDeskTestFixtures.newCase(acc.Id, UserInfo.getUserId(), 'High');
        insert c;
        Id adminId = UserInfo.getUserId();

        System.runAs(outsider) {
            ServiceDeskFactsSelector facts = new ServiceDeskFactsSelector();
            Assert.areEqual(
                ServiceDeskTestFixtures.escalationQueueId(),
                facts.selectQueueId(CaseEscalationService.ESCALATION_QUEUE)
            );
            Assert.isNull(facts.selectQueueId('No_Such_Queue'));
            Assert.areEqual(
                3,
                facts.selectCaseTeamRoleIds(
                        new Set<String>{
                            CaseTeamService.ROLE_TECHNICAL_SME,
                            CaseTeamService.ROLE_ESCALATING_AGENT,
                            CaseTeamService.ROLE_ACCOUNT_MANAGER
                        }
                    )
                    .size()
            );
            Assert.areEqual(ent.Id, facts.selectActiveEntitlementIdsByAccount(new Set<Id>{ acc.Id }).get(acc.Id));
            Assert.areEqual(adminId, facts.selectActiveAccountOwnerIds(new Set<Id>{ acc.Id }).get(acc.Id));
            Assert.isTrue(facts.selectActiveUserIds(new Set<Id>{ outsider.Id }).contains(outsider.Id));
            Assert.isTrue(
                facts.selectOpenMilestoneIds(new Set<Id>{ c.Id })
                    .get(c.Id)
                    .containsKey(CaseSlaService.MILESTONE_FIRST_RESPONSE),
                'Milestones are visible without Entitlement or Case permissions'
            );
            Assert.isTrue(facts.selectCaseTeamMemberKeys(new Set<Id>{ c.Id }).isEmpty());
        }
    }
}
