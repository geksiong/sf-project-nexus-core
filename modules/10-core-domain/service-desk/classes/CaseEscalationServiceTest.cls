/**
 * @description In-memory unit tests for the escalation policy (before update): no SOQL, no DML. The
 * facts selector is a TestStub; read-only fields (IsClosed) are set via JSON.
 */
@IsTest
private class CaseEscalationServiceTest {
    private static final Id QUEUE_ID = TestDataFactory.getFakeId(Group.SObjectType);
    private static final Id AGENT_ID = TestDataFactory.getFakeId(User.SObjectType);

    private static TestStub facts;

    private static void mockFacts(Id queueId) {
        facts = new TestStub().returns('selectQueueId', queueId);
        ServiceDeskFactsSelector.instance = (ServiceDeskFactsSelector) facts.create(ServiceDeskFactsSelector.class);
    }

    private static Case existing(String status, Boolean closed, String reason) {
        return (Case) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'Id' => TestDataFactory.getFakeId(Case.SObjectType),
                    'Status' => status,
                    'IsClosed' => closed,
                    'SLA_Breached__c' => false,
                    'Priority' => 'Low',
                    'OwnerId' => AGENT_ID,
                    'Escalation_Reason__c' => reason
                }
            ),
            Case.class
        );
    }

    private static void apply(Case changed, Case old) {
        CaseEscalationService.applyEscalationPolicy(new List<Case>{ changed }, new Map<Id, Case>{ old.Id => old });
    }

    @IsTest
    static void escalatedStatusAppliesPolicy() {
        mockFacts(QUEUE_ID);
        Case old = existing('Working', false, null);
        Case changed = old.clone(true);
        changed.Status = CaseEscalationService.STATUS_ESCALATED;

        apply(changed, old);

        Assert.areEqual(CaseEscalationService.PRIORITY_HIGH, changed.Priority);
        Assert.areEqual(QUEUE_ID, changed.OwnerId, 'Escalations route to the Tier 2 queue');
        Assert.isNotNull(changed.Escalated_On__c);
        Assert.areEqual(CaseEscalationService.REASON_MANUAL, changed.Escalation_Reason__c);
        Assert.areEqual(1, facts.callCount('selectQueueId'));
    }

    @IsTest
    static void providedReasonIsKeptAndStaleReasonReplaced() {
        mockFacts(QUEUE_ID);
        Case old = existing('Working', false, 'Previous escalation');

        Case withReason = old.clone(true);
        withReason.Status = CaseEscalationService.STATUS_ESCALATED;
        withReason.Escalation_Reason__c = 'Customer production outage';
        apply(withReason, old);
        Assert.areEqual('Customer production outage', withReason.Escalation_Reason__c);

        Case staleReason = old.clone(true);
        staleReason.Status = CaseEscalationService.STATUS_ESCALATED;
        apply(staleReason, old);
        Assert.areEqual(
            CaseEscalationService.REASON_MANUAL,
            staleReason.Escalation_Reason__c,
            'A reason left over from an earlier escalation is not reused'
        );
    }

    @IsTest
    static void slaViolationBecomesEscalation() {
        mockFacts(QUEUE_ID);
        Case old = existing('New', false, null);
        Case breached = old.clone(true);
        breached.SLA_Breached__c = true;

        apply(breached, old);

        Assert.areEqual(CaseEscalationService.STATUS_ESCALATED, breached.Status);
        Assert.areEqual(CaseEscalationService.REASON_SLA_BREACH, breached.Escalation_Reason__c);
        Assert.areEqual(QUEUE_ID, breached.OwnerId);
    }

    @IsTest
    static void violationSignalIsConsumedSoEveryViolationEscalates() {
        mockFacts(QUEUE_ID);
        Case old = existing('Working', false, null);
        Case violated = old.clone(true);
        violated.SLA_Breached__c = true;

        apply(violated, old);

        Assert.isFalse(violated.SLA_Breached__c, 'Signal reset, so the next violated milestone flips it again');
        Assert.isNotNull(violated.SLA_Violated_On__c, 'Violation time recorded for reporting');
        Assert.areEqual(CaseEscalationService.STATUS_ESCALATED, violated.Status);
    }

    @IsTest
    static void slaViolationIgnoredWhenAlreadyEscalatedOrClosed() {
        mockFacts(QUEUE_ID);
        Case escalated = existing(CaseEscalationService.STATUS_ESCALATED, false, 'Earlier');
        Case escalatedBreach = escalated.clone(true);
        escalatedBreach.SLA_Breached__c = true;
        apply(escalatedBreach, escalated);

        Case closed = existing('Closed', true, null);
        Case closedBreach = closed.clone(true);
        closedBreach.SLA_Breached__c = true;
        apply(closedBreach, closed);

        Assert.areEqual(AGENT_ID, escalatedBreach.OwnerId, 'Already escalated: not re-routed');
        Assert.isFalse(escalatedBreach.SLA_Breached__c, 'Signal is still consumed');
        Assert.isNotNull(escalatedBreach.SLA_Violated_On__c);
        Assert.areEqual('Closed', closedBreach.Status, 'Closed cases are never reopened by a breach');
        Assert.areEqual(0, facts.callCount('selectQueueId'));
    }

    @IsTest
    static void unrelatedEditsDoNotQuery() {
        mockFacts(QUEUE_ID);
        Case old = existing('Working', false, null);
        Case edited = old.clone(true);
        edited.Subject = 'Renamed';

        apply(edited, old);

        Assert.areEqual(AGENT_ID, edited.OwnerId);
        Assert.areEqual(0, facts.callCount('selectQueueId'));
    }

    @IsTest
    static void missingQueueBlocksEscalation() {
        mockFacts(null);
        Case old = existing('Working', false, null);
        Case changed = old.clone(true);
        changed.Status = CaseEscalationService.STATUS_ESCALATED;

        apply(changed, old);

        Assert.isTrue(changed.hasErrors());
        Assert.isTrue(changed.getErrors()[0].getMessage().contains('not configured'));
    }

    @IsTest
    static void isEscalationRequiresTransition() {
        Case old = existing('Working', false, null);
        Case changed = old.clone(true);
        changed.Status = CaseEscalationService.STATUS_ESCALATED;

        Assert.isTrue(CaseEscalationService.isEscalation(changed, old));
        Assert.isFalse(CaseEscalationService.isEscalation(changed, changed), 'Already escalated');
        Assert.isFalse(CaseEscalationService.isEscalation(changed, null), 'Insert is not an escalation');
    }
}
