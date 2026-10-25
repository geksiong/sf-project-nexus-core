/**
 * @description Invocable contract tests for EscalateCaseAction: success payload, input validation,
 * state checks and partial success in one bulk call.
 */
@IsTest
private class EscalateCaseActionTest {
    @TestSetup
    static void setup() {
        ServiceDeskTestFixtures.createAgentsAndRoles();
    }

    private static EscalateCaseAction.Request request(Id caseId, String reason, String smeUserId) {
        EscalateCaseAction.Request req = new EscalateCaseAction.Request();
        req.caseId = caseId;
        req.reason = reason;
        req.smeUserId = smeUserId;
        return req;
    }

    /** @description The action runs in user mode, so callers need PSG_Service_Agent's field access. */
    private static User agent() {
        return ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.AGENT_LAST_NAME);
    }

    private static Case insertCase(String status) {
        User agent = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.AGENT_LAST_NAME);
        Case c = ServiceDeskTestFixtures.newCase(null, agent.Id, 'Medium');
        c.Status = status;
        insert c;
        return c;
    }

    @IsTest
    static void escalatesWithReasonAndTechnicalSme() {
        User agent = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.AGENT_LAST_NAME);
        User sme = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.SME_LAST_NAME);
        Case c = insertCase('Working');

        List<EscalateCaseAction.Result> results;
        System.runAs(agent) {
            results = EscalateCaseAction.execute(
                new List<EscalateCaseAction.Request>{ request(c.Id, '  Customer production outage  ', sme.Id) }
            );
        }

        Assert.isTrue(results[0].isSuccess, String.valueOf(results[0]));
        Assert.areEqual(c.Id, results[0].payload.caseId);
        Assert.areEqual(CaseEscalationService.STATUS_ESCALATED, results[0].payload.status);
        Assert.isNotNull(results[0].payload.caseNumber);
        Case saved = [SELECT Escalation_Reason__c, Technical_SME__c, OwnerId FROM Case WHERE Id = :c.Id];
        Assert.areEqual('Customer production outage', saved.Escalation_Reason__c);
        Assert.areEqual(ServiceDeskTestFixtures.escalationQueueId(), saved.OwnerId);
        Map<Id, String> team = ServiceDeskTestFixtures.teamRoles(c.Id);
        Assert.areEqual(CaseTeamService.ROLE_TECHNICAL_SME, team.get(sme.Id));
        Assert.areEqual(CaseTeamService.ROLE_ESCALATING_AGENT, team.get(agent.Id));
    }

    @IsTest
    static void invalidInputsFailIndividually() {
        Case c = insertCase('Working');
        Id accountId = TestDataFactory.getFakeId(Account.SObjectType);

        List<EscalateCaseAction.Result> results;
        System.runAs(agent()) {
            results = EscalateCaseAction.execute(
                new List<EscalateCaseAction.Request>{
                    request(null, 'Reason', null),
                    request(accountId, 'Reason', null),
                    request(c.Id, ' ', null),
                    request(c.Id, 'Reason', 'not-an-id'),
                    request(c.Id, 'Reason', accountId),
                    request(c.Id, 'Valid request', null),
                    request(c.Id, 'Duplicate', null)
                }
            );
        }

        for (Integer i = 0; i < results.size(); i++) {
            if (i == 5) {
                Assert.isTrue(results[i].isSuccess, 'The valid request still succeeds: ' + results[i]);
            } else {
                Assert.isFalse(results[i].isSuccess, 'Request ' + i);
                Assert.areEqual(
                    CaseEscalationService.ERROR_INVALID_INPUT,
                    results[i].errorCode,
                    results[i].errorMessage
                );
            }
        }
    }

    @IsTest
    static void closedEscalatedAndMissingCasesAreRejected() {
        Case closed = insertCase('Closed');
        Case escalated = insertCase('Working');
        update new Case(Id = escalated.Id, Status = CaseEscalationService.STATUS_ESCALATED);
        Case deleted = insertCase('Working');
        delete deleted;

        List<EscalateCaseAction.Result> results;
        System.runAs(agent()) {
            results = EscalateCaseAction.execute(
                new List<EscalateCaseAction.Request>{
                    request(closed.Id, 'Reason', null),
                    request(escalated.Id, 'Reason', null),
                    request(deleted.Id, 'Reason', null)
                }
            );
        }

        Assert.areEqual(CaseEscalationService.ERROR_INVALID_STATE, results[0].errorCode);
        Assert.areEqual(CaseEscalationService.ERROR_INVALID_STATE, results[1].errorCode);
        Assert.isTrue(results[1].errorMessage.contains('already escalated'), results[1].errorMessage);
        Assert.areEqual(CaseEscalationService.ERROR_NOT_FOUND, results[2].errorCode);
    }

    @IsTest
    static void inactiveTechnicalSmeIsRejected() {
        User sme = ServiceDeskTestFixtures.getUser(ServiceDeskTestFixtures.SME_LAST_NAME);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = sme.Id, IsActive = false);
        }
        Case c = insertCase('Working');

        List<EscalateCaseAction.Result> results;
        System.runAs(agent()) {
            results = EscalateCaseAction.execute(
                new List<EscalateCaseAction.Request>{ request(c.Id, 'Reason', sme.Id) }
            );
        }

        Assert.areEqual(CaseEscalationService.ERROR_INVALID_INPUT, results[0].errorCode);
        Assert.isTrue(results[0].errorMessage.contains('active user'), results[0].errorMessage);
        Assert.areEqual('Working', [SELECT Status FROM Case WHERE Id = :c.Id].Status, 'Nothing was changed');
    }
}
