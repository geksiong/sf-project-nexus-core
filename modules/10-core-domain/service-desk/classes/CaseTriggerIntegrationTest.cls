/**
 * @description Database-level tests for the Case trigger: escalation from every channel, case team
 * provisioning, entitlement-driven milestones, users without service permissions, bulk limits and the
 * bypass. Rule-by-rule behaviour is covered in memory by the *ServiceTest classes.
 */
@IsTest
private class CaseTriggerIntegrationTest {
    @TestSetup
    static void setup() {
        ServiceDeskTestFixtures.createAgentsAndRoles();
    }

    private static Case reload(Id caseId) {
        return [
            SELECT Id, Status, Priority, OwnerId, EntitlementId, Escalation_Reason__c, Escalated_On__c
            FROM Case
            WHERE Id = :caseId
        ];
    }

    private static List<String> commentBodies(Id caseId) {
        List<String> bodies = new List<String>();
        for (CaseComment comment : [SELECT CommentBody, IsPublished FROM CaseComment WHERE ParentId = :caseId]) {
            Assert.isFalse(comment.IsPublished, 'Escalation comments are internal');
            bodies.add(comment.CommentBody);
        }
        return bodies;
    }

    @IsTest
    static void statusChangeEscalatesWithCommentAndCaseTeam() {
        User agent = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.AGENT_LAST_NAME);
        Account acc = TestDataFactory.createAccounts(1, true)[0];
        Case c = ServiceDeskTestFixtures.newCase(acc.Id, agent.Id, 'Medium');
        insert c;

        System.runAs(agent) {
            update new Case(Id = c.Id, Status = CaseEscalationService.STATUS_ESCALATED);
        }

        Case saved = reload(c.Id);
        Assert.areEqual(ServiceDeskTestFixtures.escalationQueueId(), saved.OwnerId);
        Assert.areEqual(CaseEscalationService.PRIORITY_HIGH, saved.Priority);
        Assert.areEqual(CaseEscalationService.REASON_MANUAL, saved.Escalation_Reason__c);
        Assert.isNotNull(saved.Escalated_On__c);
        Assert.areEqual(
            new List<String>{ 'Escalated to Tier 2: ' + CaseEscalationService.REASON_MANUAL },
            commentBodies(c.Id)
        );
        Map<Id, String> team = ServiceDeskTestFixtures.teamRoles(c.Id);
        Assert.areEqual(CaseTeamService.ROLE_ESCALATING_AGENT, team.get(agent.Id));
        Assert.areEqual(CaseTeamService.ROLE_ACCOUNT_MANAGER, team.get(UserInfo.getUserId()), 'Account owner');
    }

    @IsTest
    static void everySlaViolationEscalatesAutomatically() {
        User agent = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.AGENT_LAST_NAME);
        Case c = ServiceDeskTestFixtures.newCase(null, agent.Id, 'Low');
        insert c;

        // What the entitlement process's Flag_SLA_Breached violation action does.
        update new Case(Id = c.Id, SLA_Breached__c = true);

        Case saved = reload(c.Id);
        Assert.areEqual(CaseEscalationService.STATUS_ESCALATED, saved.Status);
        Assert.areEqual(CaseEscalationService.REASON_SLA_BREACH, saved.Escalation_Reason__c);
        Assert.areEqual(ServiceDeskTestFixtures.escalationQueueId(), saved.OwnerId);
        Assert.areEqual(CaseTeamService.ROLE_ESCALATING_AGENT, ServiceDeskTestFixtures.teamRoles(c.Id).get(agent.Id));

        // Tier 2 de-escalates; a later milestone (Resolution) is violated: the case escalates again.
        update new Case(Id = c.Id, Status = 'Working');
        update new Case(Id = c.Id, SLA_Breached__c = true);
        Assert.areEqual(CaseEscalationService.STATUS_ESCALATED, reload(c.Id).Status);
        Assert.areEqual(2, commentBodies(c.Id).size(), 'Each escalation is recorded');
    }

    /**
     * @description KI-001: a case created as Escalated lands in Tier 2 with its comment, even when created with
     * the active assignment rule (which runs after triggers and excludes escalated cases).
     */
    @IsTest
    static void caseCreatedAsEscalatedIsRoutedToTier2() {
        User agent = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.AGENT_LAST_NAME);
        Case c = ServiceDeskTestFixtures.newCase(null, agent.Id, 'Low');
        c.Status = CaseEscalationService.STATUS_ESCALATED;
        c.Escalation_Reason__c = 'Imported P1 incident';
        Database.DMLOptions options = new Database.DMLOptions();
        options.assignmentRuleHeader.useDefaultRule = true;

        Database.insert(c, options);

        Case saved = reload(c.Id);
        Assert.areEqual(ServiceDeskTestFixtures.escalationQueueId(), saved.OwnerId, 'Not re-routed to Tier 1');
        Assert.areEqual(CaseEscalationService.PRIORITY_HIGH, saved.Priority);
        Assert.areEqual(new List<String>{ 'Escalated to Tier 2: Imported P1 incident' }, commentBodies(c.Id));
    }

    @IsTest
    static void entitlementStartsMilestonesThatCompleteAsTheCaseProgresses() {
        Account acc = TestDataFactory.createAccounts(1, true)[0];
        Entitlement ent = ServiceDeskTestFixtures.createEntitlement(acc.Id);
        Case c = ServiceDeskTestFixtures.newCase(acc.Id, UserInfo.getUserId(), 'High');
        insert c;
        Assert.areEqual(ent.Id, reload(c.Id).EntitlementId, 'Linked to the account\'s active entitlement');

        update new Case(Id = c.Id, Status = 'Working');
        Map<String, CaseMilestone> milestones = new Map<String, CaseMilestone>();
        for (CaseMilestone m : [SELECT MilestoneType.Name, CompletionDate FROM CaseMilestone WHERE CaseId = :c.Id]) {
            milestones.put(m.MilestoneType.Name, m);
        }
        Assert.isNotNull(
            milestones.get(CaseSlaService.MILESTONE_FIRST_RESPONSE)?.CompletionDate,
            String.valueOf(milestones)
        );
        Assert.isNull(milestones.get(CaseSlaService.MILESTONE_RESOLUTION).CompletionDate);

        update new Case(Id = c.Id, Status = 'Closed');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM CaseMilestone WHERE CaseId = :c.Id AND CompletionDate = NULL],
            'Closing completes Resolution'
        );
    }

    /**
     * @description Escalation and case team rules are invariants: they apply whoever saves the case,
     * including users without the service permission sets (integrations, automation, agents via MCP).
     */
    @IsTest
    static void rulesApplyToUsersWithoutServicePermissions() {
        User outsider = TestDataFactory.createTestUser('Standard User', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert outsider;
        }
        Case c = ServiceDeskTestFixtures.newCase(TestDataFactory.createAccounts(1, true)[0].Id, outsider.Id, 'Low');
        insert c;

        System.runAs(outsider) {
            update new Case(Id = c.Id, Status = CaseEscalationService.STATUS_ESCALATED);
        }

        Assert.areEqual(ServiceDeskTestFixtures.escalationQueueId(), reload(c.Id).OwnerId);
        Map<Id, String> team = ServiceDeskTestFixtures.teamRoles(c.Id);
        Assert.areEqual(CaseTeamService.ROLE_ESCALATING_AGENT, team.get(outsider.Id));
        Assert.areEqual(CaseTeamService.ROLE_ACCOUNT_MANAGER, team.get(UserInfo.getUserId()));
    }

    @IsTest
    static void bulkEscalationOf200StaysWithinLimits() {
        User agent = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.AGENT_LAST_NAME);
        // No entitlement: the platform's milestone engine would add ~30s for 200 cases without exercising
        // more Nexus code (milestone completion is covered above and in CaseSlaServiceTest).
        Account acc = TestDataFactory.createAccounts(1, true)[0];
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            cases.add(ServiceDeskTestFixtures.newCase(acc.Id, agent.Id, 'Medium'));
        }
        insert cases;

        Test.startTest();
        for (Case c : cases) {
            c.Status = CaseEscalationService.STATUS_ESCALATED;
        }
        update cases;
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Case WHERE Status = :CaseEscalationService.STATUS_ESCALATED]);
        Assert.areEqual(200, [SELECT COUNT() FROM CaseComment]);
        Assert.areEqual(400, [SELECT COUNT() FROM CaseTeamMember], 'Escalating Agent + Account Manager per case');
        Assert.isTrue(queriesUsed < 15, 'Trigger logic must be bulkified, used ' + queriesUsed + ' queries');
    }

    @IsTest
    static void bypassSkipsAllCaseRules() {
        User agent = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.AGENT_LAST_NAME);
        Case c = ServiceDeskTestFixtures.newCase(null, agent.Id, 'Low');
        insert c;
        BypassService.setTriggerBypass('Case', true);

        update new Case(Id = c.Id, Status = CaseEscalationService.STATUS_ESCALATED);

        Case saved = reload(c.Id);
        Assert.areEqual(agent.Id, saved.OwnerId, 'Escalation policy bypassed');
        Assert.isTrue(ServiceDeskTestFixtures.teamRoles(c.Id).isEmpty(), 'Case team provisioning bypassed');
    }
}
