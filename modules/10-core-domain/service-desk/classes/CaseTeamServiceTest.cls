/**
 * @description In-memory unit tests for case team planning (CaseTeamService.planCaseTeamMembers):
 * which members the rules require, precedence and de-duplication. Insertion is covered by
 * CaseTriggerIntegrationTest.
 */
@IsTest
private class CaseTeamServiceTest {
    private static final Id AGENT_ID = TestDataFactory.getFakeId(User.SObjectType);
    private static final Id SME_ID = TestDataFactory.getFakeId(User.SObjectType);
    private static final Id ACCOUNT_OWNER_ID = TestDataFactory.getFakeId(User.SObjectType);
    private static final Id QUEUE_ID = TestDataFactory.getFakeId(Group.SObjectType);
    private static final Id ACCOUNT_ID = TestDataFactory.getFakeId(Account.SObjectType);
    private static final Id SME_ROLE_ID = fakeRoleId(1);
    private static final Id AGENT_ROLE_ID = fakeRoleId(2);
    private static final Id MANAGER_ROLE_ID = fakeRoleId(3);

    private static TestStub facts;

    /** @description CaseTeamRole has no describe key prefix, so TestDataFactory.getFakeId cannot build one. */
    private static Id fakeRoleId(Integer n) {
        return Id.valueOf('0B7' + String.valueOf(n).leftPad(12, '0'));
    }

    private static void mockFacts(Map<Id, Id> accountOwners, Set<String> existingKeys) {
        facts = new TestStub()
            .returns('selectActiveAccountOwnerIds', accountOwners)
            .returns(
                'selectCaseTeamRoleIds',
                new Map<String, Id>{
                    CaseTeamService.ROLE_TECHNICAL_SME => SME_ROLE_ID,
                    CaseTeamService.ROLE_ESCALATING_AGENT => AGENT_ROLE_ID,
                    CaseTeamService.ROLE_ACCOUNT_MANAGER => MANAGER_ROLE_ID
                }
            )
            .returns('selectCaseTeamMemberKeys', existingKeys);
        ServiceDeskFactsSelector.instance = (ServiceDeskFactsSelector) facts.create(ServiceDeskFactsSelector.class);
    }

    private static Case working(Id ownerId) {
        return new Case(
            Id = TestDataFactory.getFakeId(Case.SObjectType),
            Status = 'Working',
            Priority = 'Low',
            OwnerId = ownerId,
            AccountId = ACCOUNT_ID
        );
    }

    /** @description The escalated version of `old`, as the before-update policy leaves it. */
    private static Case escalated(Case old) {
        Case c = old.clone(true);
        c.Status = CaseEscalationService.STATUS_ESCALATED;
        c.Priority = CaseTeamService.PRIORITY_HIGH;
        c.OwnerId = QUEUE_ID;
        return c;
    }

    private static List<CaseTeamMember> plan(Case changed, Case old) {
        return CaseTeamService.planCaseTeamMembers(
            new List<Case>{ changed },
            old == null ? null : new Map<Id, Case>{ old.Id => old }
        );
    }

    private static Map<Id, Id> rolesByMember(List<CaseTeamMember> members) {
        Map<Id, Id> roles = new Map<Id, Id>();
        for (CaseTeamMember m : members) {
            roles.put(m.MemberId, m.TeamRoleId);
        }
        return roles;
    }

    @IsTest
    static void escalationAddsPreviousOwnerAndAccountManager() {
        mockFacts(new Map<Id, Id>{ ACCOUNT_ID => ACCOUNT_OWNER_ID }, new Set<String>());
        Case old = working(AGENT_ID);

        Map<Id, Id> roles = rolesByMember(plan(escalated(old), old));

        Assert.areEqual(2, roles.size(), String.valueOf(roles));
        Assert.areEqual(AGENT_ROLE_ID, roles.get(AGENT_ID), 'Previous owner keeps access as Escalating Agent');
        Assert.areEqual(MANAGER_ROLE_ID, roles.get(ACCOUNT_OWNER_ID), 'High priority adds the account owner');
    }

    @IsTest
    static void smeTakesPrecedenceOverOtherRoles() {
        mockFacts(new Map<Id, Id>{ ACCOUNT_ID => AGENT_ID }, new Set<String>());
        Case old = working(AGENT_ID);
        Case changed = escalated(old);
        changed.Technical_SME__c = AGENT_ID;

        List<CaseTeamMember> members = plan(changed, old);

        Assert.areEqual(1, members.size(), 'One membership per user and case');
        Assert.areEqual(SME_ROLE_ID, members[0].TeamRoleId);
    }

    @IsTest
    static void queueOwnersAndCaseOwnersAreNotAdded() {
        mockFacts(new Map<Id, Id>(), new Set<String>());
        Case queueOwned = working(QUEUE_ID);
        Assert.isTrue(plan(escalated(queueOwned), queueOwned).isEmpty(), 'Queues cannot join a case team');

        mockFacts(new Map<Id, Id>{ ACCOUNT_ID => AGENT_ID }, new Set<String>());

        Case raised = working(AGENT_ID);
        Case highPriority = raised.clone(true);
        highPriority.Priority = CaseTeamService.PRIORITY_HIGH;
        Assert.isTrue(plan(highPriority, raised).isEmpty(), 'Account owner who already owns the case is skipped');
    }

    @IsTest
    static void inactiveAccountOwnerIsSkipped() {
        mockFacts(new Map<Id, Id>(), new Set<String>());
        Case inserted = working(AGENT_ID);
        inserted.Priority = CaseTeamService.PRIORITY_HIGH;

        Assert.isTrue(plan(inserted, null).isEmpty());
        Assert.areEqual(1, facts.callCount('selectActiveAccountOwnerIds'));
    }

    @IsTest
    static void highPriorityInsertAddsAccountManager() {
        mockFacts(new Map<Id, Id>{ ACCOUNT_ID => ACCOUNT_OWNER_ID }, new Set<String>());
        Case inserted = working(AGENT_ID);
        inserted.Priority = CaseTeamService.PRIORITY_HIGH;

        Assert.areEqual(MANAGER_ROLE_ID, rolesByMember(plan(inserted, null)).get(ACCOUNT_OWNER_ID));
    }

    @IsTest
    static void existingMembersAreNotDuplicated() {
        Case old = working(AGENT_ID);
        mockFacts(
            new Map<Id, Id>{ ACCOUNT_ID => ACCOUNT_OWNER_ID },
            new Set<String>{ old.Id + ':' + AGENT_ID, old.Id + ':' + ACCOUNT_OWNER_ID }
        );

        Assert.isTrue(plan(escalated(old), old).isEmpty());
    }

    @IsTest
    static void missingRoleIsLoggedAndSkipped() {
        mockFacts(new Map<Id, Id>(), new Set<String>());
        facts.returns('selectCaseTeamRoleIds', new Map<String, Id>());
        Case old = working(AGENT_ID);
        Case changed = old.clone(true);
        changed.Technical_SME__c = SME_ID;

        Assert.isTrue(plan(changed, old).isEmpty());
        Assert.isTrue(Logger.getBufferSize() > 0, 'Missing role configuration is logged as an error');
    }

    @IsTest
    static void unrelatedEditsDoNotQuery() {
        mockFacts(new Map<Id, Id>(), new Set<String>());
        Case old = working(AGENT_ID);
        Case edited = old.clone(true);
        edited.Subject = 'Renamed';

        Assert.isTrue(plan(edited, old).isEmpty());
        Assert.areEqual(0, facts.callCount('selectCaseTeamRoleIds'));
        Assert.areEqual(0, facts.callCount('selectActiveAccountOwnerIds'));
    }
}
