/**
 * @description In-memory unit tests for entitlement assignment and milestone completion planning.
 * Platform-created milestones are covered by CaseTriggerIntegrationTest.
 */
@IsTest
private class CaseSlaServiceTest {
    private static final Id ACCOUNT_ID = TestDataFactory.getFakeId(Account.SObjectType);
    private static final Id ENTITLEMENT_ID = TestDataFactory.getFakeId(Entitlement.SObjectType);
    private static final Id OTHER_ENTITLEMENT_ID = TestDataFactory.getFakeId(Entitlement.SObjectType);
    private static final Id FIRST_RESPONSE_ID = TestDataFactory.getFakeId(CaseMilestone.SObjectType);
    private static final Id RESOLUTION_ID = TestDataFactory.getFakeId(CaseMilestone.SObjectType);

    private static TestStub facts;

    private static void mockFacts(Map<Id, Map<String, Id>> openMilestones) {
        facts = new TestStub()
            .returns('selectActiveEntitlementIdsByAccount', new Map<Id, Id>{ ACCOUNT_ID => ENTITLEMENT_ID })
            .returns('selectOpenMilestoneIds', openMilestones);
        ServiceDeskFactsSelector.instance = (ServiceDeskFactsSelector) facts.create(ServiceDeskFactsSelector.class);
    }

    private static Case entitled(Id caseId, String status, Boolean closed) {
        return (Case) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'Id' => caseId,
                    'Status' => status,
                    'IsClosed' => closed,
                    'EntitlementId' => ENTITLEMENT_ID
                }
            ),
            Case.class
        );
    }

    private static Set<Id> plannedIds(Case changed, Case old) {
        Set<Id> ids = new Set<Id>();
        for (
            CaseMilestone m : CaseSlaService.planMilestoneCompletions(
                new List<Case>{ changed },
                new Map<Id, Case>{ old.Id => old }
            )
        ) {
            Assert.isNotNull(m.CompletionDate);
            ids.add(m.Id);
        }
        return ids;
    }

    private static Map<Id, Map<String, Id>> openMilestones(Id caseId, Boolean includeFirstResponse) {
        Map<String, Id> open = new Map<String, Id>{ CaseSlaService.MILESTONE_RESOLUTION => RESOLUTION_ID };
        if (includeFirstResponse) {
            open.put(CaseSlaService.MILESTONE_FIRST_RESPONSE, FIRST_RESPONSE_ID);
        }
        return new Map<Id, Map<String, Id>>{ caseId => open };
    }

    @IsTest
    static void newCasesInheritTheAccountsActiveEntitlement() {
        mockFacts(null);
        Case fromAccount = new Case(AccountId = ACCOUNT_ID);
        Case alreadyEntitled = new Case(AccountId = ACCOUNT_ID, EntitlementId = OTHER_ENTITLEMENT_ID);
        Case noAccount = new Case();

        CaseSlaService.assignEntitlements(new List<Case>{ fromAccount, alreadyEntitled, noAccount }, null);

        Assert.areEqual(ENTITLEMENT_ID, fromAccount.EntitlementId);
        Assert.areEqual(OTHER_ENTITLEMENT_ID, alreadyEntitled.EntitlementId, 'An explicit entitlement wins');
        Assert.isNull(noAccount.EntitlementId);
        Assert.areEqual(new Set<Id>{ ACCOUNT_ID }, facts.lastArguments('selectActiveEntitlementIdsByAccount')[0]);
    }

    @IsTest
    static void casesWithoutAccountsDoNotQuery() {
        mockFacts(null);
        CaseSlaService.assignEntitlements(new List<Case>{ new Case() }, null);
        Assert.areEqual(0, facts.callCount('selectActiveEntitlementIdsByAccount'));
    }

    @IsTest
    static void casesGivenAnAccountLaterInheritItsEntitlement() {
        mockFacts(null);
        Case unassigned = new Case(Id = TestDataFactory.getFakeId(Case.SObjectType));
        Case accountAdded = unassigned.clone(true);
        accountAdded.AccountId = ACCOUNT_ID;
        Case accountUnchanged = new Case(Id = TestDataFactory.getFakeId(Case.SObjectType), AccountId = ACCOUNT_ID);

        CaseSlaService.assignEntitlements(
            new List<Case>{ accountAdded, accountUnchanged },
            new Map<Id, Case>{ unassigned.Id => unassigned, accountUnchanged.Id => accountUnchanged.clone(true) }
        );

        Assert.areEqual(ENTITLEMENT_ID, accountAdded.EntitlementId);
        Assert.isNull(accountUnchanged.EntitlementId, 'Only a new account triggers the lookup');
    }

    @IsTest
    static void leavingNewCompletesFirstResponse() {
        Id caseId = TestDataFactory.getFakeId(Case.SObjectType);
        mockFacts(openMilestones(caseId, true));

        Assert.areEqual(
            new Set<Id>{ FIRST_RESPONSE_ID },
            plannedIds(entitled(caseId, 'Working', false), entitled(caseId, 'New', false))
        );
    }

    @IsTest
    static void escalationIsNotAFirstResponse() {
        Id caseId = TestDataFactory.getFakeId(Case.SObjectType);
        mockFacts(openMilestones(caseId, true));

        Assert.isTrue(
            plannedIds(entitled(caseId, CaseEscalationService.STATUS_ESCALATED, false), entitled(caseId, 'New', false))
                .isEmpty(),
            'Escalating (e.g. on a missed First Response) does not complete First Response'
        );
        Assert.areEqual(
            new Set<Id>{ FIRST_RESPONSE_ID },
            plannedIds(
                entitled(caseId, 'Working', false),
                entitled(caseId, CaseEscalationService.STATUS_ESCALATED, false)
            ),
            'Tier 2 starting work is the first response'
        );
    }

    @IsTest
    static void closingCompletesEveryOpenMilestone() {
        Id caseId = TestDataFactory.getFakeId(Case.SObjectType);
        mockFacts(openMilestones(caseId, true));
        Assert.areEqual(
            new Set<Id>{ FIRST_RESPONSE_ID, RESOLUTION_ID },
            plannedIds(entitled(caseId, 'Closed', true), entitled(caseId, 'New', false))
        );

        mockFacts(openMilestones(caseId, false));
        Assert.areEqual(
            new Set<Id>{ RESOLUTION_ID },
            plannedIds(entitled(caseId, 'Closed', true), entitled(caseId, 'Working', false)),
            'Milestones already completed are left alone'
        );
    }

    @IsTest
    static void otherChangesAndUnentitledCasesDoNotQuery() {
        Id caseId = TestDataFactory.getFakeId(Case.SObjectType);
        mockFacts(openMilestones(caseId, true));
        Assert.isTrue(plannedIds(entitled(caseId, 'Working', false), entitled(caseId, 'Working', false)).isEmpty());

        Case unentitled = entitled(caseId, 'Closed', true);
        unentitled.EntitlementId = null;
        Assert.isTrue(plannedIds(unentitled, entitled(caseId, 'New', false)).isEmpty());
        Assert.areEqual(0, facts.callCount('selectOpenMilestoneIds'));
    }
}
