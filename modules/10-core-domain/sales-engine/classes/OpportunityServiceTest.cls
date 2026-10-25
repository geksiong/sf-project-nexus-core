/**
 * @description In-memory unit tests for OpportunityService rules: no SOQL, no DML. Selectors are
 * replaced with TestStub mocks and relationship data is built via JSON. Trigger wiring and bulk
 * behaviour against the database live in OpportunityTriggerIntegrationTest.
 */
@IsTest
private class OpportunityServiceTest {
    private static final Id REP_ID = TestDataFactory.getFakeId(User.SObjectType);
    private static final Id MANAGER_ID = TestDataFactory.getFakeId(User.SObjectType);
    private static final Id EXEC_ID = TestDataFactory.getFakeId(User.SObjectType);
    private static final Id ACCOUNT_ID = TestDataFactory.getFakeId(Account.SObjectType);
    private static final Id CREDIT_HOLD_ACCOUNT_ID = TestDataFactory.getFakeId(Account.SObjectType);

    private static TestStub usersStub;
    private static TestStub accountsStub;
    private static TestStub opportunitiesStub;

    /** @description Installs selector mocks: rep -> manager -> exec chain and two accounts. */
    private static void mockSelectors(List<Opportunity> details) {
        SalesEngineTestFixtures.useStandardTiers();
        usersStub = new TestStub()
            .returns(
                'selectByIdWithManagerChain',
                new Map<Id, User>{
                    REP_ID => user(REP_ID, MANAGER_ID, true, EXEC_ID, true),
                    MANAGER_ID => user(MANAGER_ID, EXEC_ID, true, null, false),
                    EXEC_ID => user(EXEC_ID, null, false, null, false)
                }
            );
        accountsStub = new TestStub()
            .returns(
                'selectByIdWithCreditStatus',
                new Map<Id, Account>{
                    ACCOUNT_ID => new Account(Id = ACCOUNT_ID, Credit_Hold__c = false),
                    CREDIT_HOLD_ACCOUNT_ID => new Account(Id = CREDIT_HOLD_ACCOUNT_ID, Credit_Hold__c = true)
                }
            );
        opportunitiesStub = new TestStub().returns('selectByIdWithDetails', details);
        UsersSelector.instance = (UsersSelector) usersStub.create(UsersSelector.class);
        AccountsSelector.instance = (AccountsSelector) accountsStub.create(AccountsSelector.class);
        OpportunitiesSelector.instance = (OpportunitiesSelector) opportunitiesStub.create(OpportunitiesSelector.class);
    }

    private static User user(Id userId, Id managerId, Boolean managerActive, Id grandManagerId, Boolean grandActive) {
        Map<String, Object> fields = new Map<String, Object>{ 'Id' => userId, 'ManagerId' => managerId };
        if (managerId != null) {
            Map<String, Object> manager = new Map<String, Object>{
                'Id' => managerId,
                'IsActive' => managerActive,
                'ManagerId' => grandManagerId
            };
            if (grandManagerId != null) {
                manager.put('Manager', new Map<String, Object>{ 'Id' => grandManagerId, 'IsActive' => grandActive });
            }
            fields.put('Manager', manager);
        }
        return (User) JSON.deserialize(JSON.serialize(fields), User.class);
    }

    /** @description Opportunity as returned by OpportunitiesSelector, with an in-memory contact role list. */
    private static Opportunity details(Id oppId, Boolean hasPrimaryContact) {
        List<Object> roles = new List<Object>{
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'OpportunityContactRole' },
                'IsPrimary' => hasPrimaryContact
            }
        };
        return (Opportunity) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'Id' => oppId,
                    'OpportunityContactRoles' => new Map<String, Object>{
                        'totalSize' => 1,
                        'done' => true,
                        'records' => roles
                    }
                }
            ),
            Opportunity.class
        );
    }

    private static Opportunity opp(Id accountId, String stage, Decimal discount) {
        return new Opportunity(
            Name = 'Unit',
            AccountId = accountId,
            OwnerId = REP_ID,
            StageName = stage,
            CloseDate = Date.today(),
            Discount_Percentage__c = discount
        );
    }

    /** @description Pair of (old, new) records sharing a fake Id, as Trigger.oldMap / Trigger.new would. */
    private static Opportunity withId(Opportunity record) {
        record.Id = TestDataFactory.getFakeId(Opportunity.SObjectType);
        return record;
    }

    private static String errors(SObject record) {
        List<String> messages = new List<String>();
        for (Database.Error err : record.getErrors()) {
            messages.add(err.getMessage());
        }
        return String.join(messages, ' | ');
    }

    private static void applyPolicy(Opportunity newOpp, Opportunity oldOpp) {
        OpportunityService.applyDiscountApprovalPolicy(
            new List<Opportunity>{ newOpp },
            oldOpp == null ? null : new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
        );
    }

    private static void validate(Opportunity newOpp, Opportunity oldOpp) {
        OpportunityService.validateStageProgression(
            new List<Opportunity>{ newOpp },
            oldOpp == null ? null : new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
        );
    }

    // ---------------------------------------------------------------------------------------------
    // Discount approval policy
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void derivesTierAndStatusFromDiscount() {
        mockSelectors(new List<Opportunity>());
        List<Opportunity> opps = new List<Opportunity>{
            opp(ACCOUNT_ID, 'Prospecting', null),
            opp(ACCOUNT_ID, 'Prospecting', 10),
            opp(ACCOUNT_ID, 'Prospecting', 15),
            opp(ACCOUNT_ID, 'Prospecting', 30)
        };

        OpportunityService.applyDiscountApprovalPolicy(opps, null);

        Assert.isNull(opps[0].Approval_Tier__c);
        Assert.areEqual(OpportunityService.STATUS_NOT_REQUIRED, opps[0].Discount_Approval_Status__c);
        Assert.isNull(opps[1].Approval_Tier__c, 'Threshold is exclusive: 10% needs no approval');
        Assert.areEqual('Tier 1', opps[2].Approval_Tier__c);
        Assert.areEqual(OpportunityService.STATUS_NOT_SUBMITTED, opps[2].Discount_Approval_Status__c);
        Assert.isNull(opps[2].Executive_Approver__c);
        Assert.areEqual('Tier 2', opps[3].Approval_Tier__c);
        Assert.areEqual(
            EXEC_ID,
            opps[3].Executive_Approver__c,
            'Executive approver is the owner\'s manager\'s manager'
        );
        Assert.areEqual(1, usersStub.callCount('selectByIdWithManagerChain'), 'Owners are resolved in one bulk query');
    }

    @IsTest
    static void rejectsOutOfRangeDiscount() {
        mockSelectors(new List<Opportunity>());
        Opportunity negative = opp(ACCOUNT_ID, 'Prospecting', -1);
        Opportunity tooHigh = opp(ACCOUNT_ID, 'Prospecting', 120);

        OpportunityService.applyDiscountApprovalPolicy(new List<Opportunity>{ negative, tooHigh }, null);

        Assert.isTrue(errors(negative).contains('between 0% and 100%'), errors(negative));
        Assert.isTrue(errors(tooHigh).contains('between 0% and 100%'), errors(tooHigh));
    }

    @IsTest
    static void loweringApprovedDiscountKeepsApprovalRaisingResets() {
        mockSelectors(new List<Opportunity>());
        Opportunity approved = withId(opp(ACCOUNT_ID, 'Negotiation/Review', 20));
        approved.Approval_Tier__c = 'Tier 1';
        approved.Discount_Approval_Status__c = OpportunityService.STATUS_APPROVED;

        Opportunity lowered = approved.clone(true);
        lowered.Discount_Percentage__c = 12;
        applyPolicy(lowered, approved);
        Assert.areEqual(OpportunityService.STATUS_APPROVED, lowered.Discount_Approval_Status__c);

        Opportunity raised = approved.clone(true);
        raised.Discount_Percentage__c = 22;
        applyPolicy(raised, approved);
        Assert.areEqual(OpportunityService.STATUS_NOT_SUBMITTED, raised.Discount_Approval_Status__c);

        Opportunity removed = approved.clone(true);
        removed.Discount_Percentage__c = 5;
        applyPolicy(removed, approved);
        Assert.isNull(removed.Approval_Tier__c);
        Assert.areEqual(OpportunityService.STATUS_NOT_REQUIRED, removed.Discount_Approval_Status__c);
    }

    @IsTest
    static void rejectedDiscountChangeRequiresResubmission() {
        mockSelectors(new List<Opportunity>());
        Opportunity rejected = withId(opp(ACCOUNT_ID, 'Negotiation/Review', 20));
        rejected.Discount_Approval_Status__c = OpportunityService.STATUS_REJECTED;
        Opportunity changed = rejected.clone(true);
        changed.Discount_Percentage__c = 18;

        applyPolicy(changed, rejected);

        Assert.areEqual(OpportunityService.STATUS_NOT_SUBMITTED, changed.Discount_Approval_Status__c);
    }

    @IsTest
    static void blocksDiscountChangeWhilePending() {
        mockSelectors(new List<Opportunity>());
        Opportunity pending = withId(opp(ACCOUNT_ID, 'Negotiation/Review', 20));
        pending.Discount_Approval_Status__c = OpportunityService.STATUS_PENDING;
        Opportunity changed = pending.clone(true);
        changed.Discount_Percentage__c = 22;

        applyPolicy(changed, pending);

        Assert.isTrue(errors(changed).contains('approval is pending'), errors(changed));
    }

    @IsTest
    static void unchangedDiscountAndOwnerSkipsPolicyAndQueries() {
        mockSelectors(new List<Opportunity>());
        Opportunity existing = withId(opp(ACCOUNT_ID, 'Negotiation/Review', 30));
        existing.Approval_Tier__c = 'Tier 2';
        existing.Discount_Approval_Status__c = OpportunityService.STATUS_PENDING;
        Opportunity statusOnlyChange = existing.clone(true);
        statusOnlyChange.Discount_Approval_Status__c = OpportunityService.STATUS_APPROVED;

        applyPolicy(statusOnlyChange, existing);

        Assert.areEqual(OpportunityService.STATUS_APPROVED, statusOnlyChange.Discount_Approval_Status__c);
        Assert.areEqual(
            0,
            usersStub.callCount('selectByIdWithManagerChain'),
            'Approval field updates must not re-query'
        );
    }

    @IsTest
    static void ownerChangeRecalculatesExecutiveApprover() {
        mockSelectors(new List<Opportunity>());
        Opportunity existing = withId(opp(ACCOUNT_ID, 'Negotiation/Review', 30));
        existing.Approval_Tier__c = 'Tier 2';
        existing.Executive_Approver__c = EXEC_ID;

        Opportunity toManager = existing.clone(true);
        toManager.OwnerId = MANAGER_ID;
        applyPolicy(toManager, existing);
        Assert.areEqual(EXEC_ID, toManager.Executive_Approver__c, 'Falls back to the owner\'s manager');

        Opportunity toExec = existing.clone(true);
        toExec.OwnerId = EXEC_ID;
        applyPolicy(toExec, existing);
        Assert.isNull(toExec.Executive_Approver__c, 'No manager chain: no executive approver');
    }

    @IsTest
    static void inactiveGrandManagerFallsBackToManager() {
        mockSelectors(new List<Opportunity>());
        usersStub.returns(
            'selectByIdWithManagerChain',
            new Map<Id, User>{ REP_ID => user(REP_ID, MANAGER_ID, true, EXEC_ID, false) }
        );

        Opportunity record = opp(ACCOUNT_ID, 'Prospecting', 30);
        applyPolicy(record, null);

        Assert.areEqual(MANAGER_ID, record.Executive_Approver__c);
    }

    @IsTest
    static void droppingToTierOneClearsExecutiveApprover() {
        mockSelectors(new List<Opportunity>());
        Opportunity existing = withId(opp(ACCOUNT_ID, 'Negotiation/Review', 30));
        existing.Approval_Tier__c = 'Tier 2';
        existing.Executive_Approver__c = EXEC_ID;
        Opportunity lowered = existing.clone(true);
        lowered.Discount_Percentage__c = 15;

        applyPolicy(lowered, existing);

        Assert.areEqual('Tier 1', lowered.Approval_Tier__c);
        Assert.isNull(lowered.Executive_Approver__c);
    }

    @IsTest
    static void tiersAreSortedByThresholdAndLoadLazily() {
        OpportunityService.approvalTiers = new List<Discount_Approval_Tier__mdt>{
            new Discount_Approval_Tier__mdt(Discount_Threshold__c = 5, Approval_Tier__c = 'Tier 1'),
            new Discount_Approval_Tier__mdt(Discount_Threshold__c = 40, Approval_Tier__c = 'Tier 2')
        };
        Assert.areEqual('Tier 2', OpportunityService.resolveTier(41));
        Assert.areEqual('Tier 1', OpportunityService.resolveTier(6));
        Assert.isNull(OpportunityService.resolveTier(5));
        Assert.isNull(OpportunityService.resolveTier(null));

        OpportunityService.approvalTiers = null;
        Assert.isNotNull(OpportunityService.approvalTiers, 'Lazily reloads deployed Discount_Approval_Tier__mdt');
    }

    // ---------------------------------------------------------------------------------------------
    // Stage gates
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void creditHoldBlocksClosedWonOnInsertAndUpdate() {
        Opportunity existing = withId(opp(CREDIT_HOLD_ACCOUNT_ID, 'Negotiation/Review', null));
        mockSelectors(new List<Opportunity>{ details(existing.Id, true) });

        Opportunity inserted = opp(CREDIT_HOLD_ACCOUNT_ID, OpportunityService.STAGE_CLOSED_WON, null);
        validate(inserted, null);
        Assert.isTrue(errors(inserted).contains('Credit Hold'), errors(inserted));

        Opportunity closing = existing.clone(true);
        closing.StageName = OpportunityService.STAGE_CLOSED_WON;
        validate(closing, existing);
        Assert.isTrue(errors(closing).contains('Credit Hold'), errors(closing));
    }

    @IsTest
    static void discountApprovalGatesClosedWon() {
        Opportunity existing = withId(opp(ACCOUNT_ID, 'Negotiation/Review', 15));
        existing.Approval_Tier__c = 'Tier 1';
        existing.Discount_Approval_Status__c = OpportunityService.STATUS_NOT_SUBMITTED;
        mockSelectors(new List<Opportunity>{ details(existing.Id, true) });

        Opportunity unapproved = existing.clone(true);
        unapproved.StageName = OpportunityService.STAGE_CLOSED_WON;
        validate(unapproved, existing);
        Assert.isTrue(errors(unapproved).contains('Tier 1 approval'), errors(unapproved));

        Opportunity approved = existing.clone(true);
        approved.StageName = OpportunityService.STAGE_CLOSED_WON;
        approved.Discount_Approval_Status__c = OpportunityService.STATUS_APPROVED;
        validate(approved, existing);
        Assert.isFalse(approved.hasErrors(), errors(approved));
    }

    @IsTest
    static void primaryContactRoleRequiredToCloseWonOnUpdate() {
        Opportunity withoutPrimary = withId(opp(ACCOUNT_ID, 'Negotiation/Review', null));
        Opportunity withPrimary = withId(opp(ACCOUNT_ID, 'Negotiation/Review', null));
        mockSelectors(new List<Opportunity>{ details(withoutPrimary.Id, false), details(withPrimary.Id, true) });

        Opportunity closingWithout = withoutPrimary.clone(true);
        closingWithout.StageName = OpportunityService.STAGE_CLOSED_WON;
        Opportunity closingWith = withPrimary.clone(true);
        closingWith.StageName = OpportunityService.STAGE_CLOSED_WON;
        OpportunityService.validateStageProgression(
            new List<Opportunity>{ closingWithout, closingWith },
            new Map<Id, Opportunity>{ withoutPrimary.Id => withoutPrimary, withPrimary.Id => withPrimary }
        );

        Assert.isTrue(errors(closingWithout).contains('Primary Contact Role'), errors(closingWithout));
        Assert.isFalse(closingWith.hasErrors(), errors(closingWith));
        Assert.areEqual(
            1,
            opportunitiesStub.callCount('selectByIdWithDetails'),
            'One bulk query for all closing deals'
        );
    }

    @IsTest
    static void closedWonInsertSkipsPrimaryContactCheck() {
        mockSelectors(new List<Opportunity>());
        Opportunity migrated = opp(ACCOUNT_ID, OpportunityService.STAGE_CLOSED_WON, null);

        validate(migrated, null);

        Assert.isFalse(migrated.hasErrors(), 'Contact roles cannot exist before insert: ' + errors(migrated));
    }

    @IsTest
    static void allGateViolationsAreReportedTogether() {
        Opportunity existing = withId(opp(CREDIT_HOLD_ACCOUNT_ID, 'Negotiation/Review', 30));
        existing.Approval_Tier__c = 'Tier 2';
        existing.Discount_Approval_Status__c = OpportunityService.STATUS_NOT_SUBMITTED;
        mockSelectors(new List<Opportunity>{ details(existing.Id, false) });

        Opportunity closing = existing.clone(true);
        closing.StageName = OpportunityService.STAGE_CLOSED_WON;
        validate(closing, existing);

        String message = errors(closing);
        Assert.areEqual(1, closing.getErrors().size(), 'Violations are combined into one record error');
        Assert.isTrue(message.contains('Credit Hold'), message);
        Assert.isTrue(message.contains('Tier 2 approval'), message);
        Assert.isTrue(message.contains('Primary Contact Role'), message);
    }

    @IsTest
    static void lossReasonRequiredForClosedLost() {
        mockSelectors(new List<Opportunity>());
        Opportunity existing = withId(opp(ACCOUNT_ID, 'Negotiation/Review', null));

        Opportunity withoutReason = existing.clone(true);
        withoutReason.StageName = OpportunityService.STAGE_CLOSED_LOST;
        validate(withoutReason, existing);
        Assert.isTrue(errors(withoutReason).contains('Loss Reason'), errors(withoutReason));

        Opportunity withReason = existing.clone(true);
        withReason.StageName = OpportunityService.STAGE_CLOSED_LOST;
        withReason.Loss_Reason__c = 'Competitor';
        validate(withReason, existing);
        Assert.isFalse(withReason.hasErrors(), errors(withReason));
    }

    @IsTest
    static void recordsNotTransitioningAreNotRevalidated() {
        mockSelectors(new List<Opportunity>());
        Opportunity alreadyWon = withId(opp(CREDIT_HOLD_ACCOUNT_ID, OpportunityService.STAGE_CLOSED_WON, null));
        Opportunity edited = alreadyWon.clone(true);
        edited.Name = 'Renamed';

        validate(edited, alreadyWon);

        Assert.isFalse(edited.hasErrors(), errors(edited));
        Assert.areEqual(0, accountsStub.callCount('selectByIdWithCreditStatus'));
        Assert.areEqual(0, opportunitiesStub.callCount('selectByIdWithDetails'));
    }
}
