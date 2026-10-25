/**
 * @description Integration tests for the Opportunity Discount Approval process: verifies the
 * service-computed tier fields route Tier 1 to the owner's manager and Tier 2 on to the executive.
 */
@IsTest
private class OpportunityDiscountApprovalTest {
    @TestSetup
    static void setup() {
        SalesEngineTestFixtures.createManagerChain();
        TestDataFactory.createAccounts(1, true);
    }

    private static Opportunity createRepOpp(Decimal discount) {
        SalesEngineTestFixtures.useStandardTiers();
        User rep = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.REP_LAST_NAME);
        Opportunity opp = TestDataFactory.createOpportunities([SELECT Id FROM Account LIMIT 1].Id, 1, false)[0];
        opp.OwnerId = rep.Id;
        opp.Discount_Percentage__c = discount;
        insert opp;
        return opp;
    }

    private static Approval.ProcessResult submitAsOwner(Id oppId) {
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(oppId);
        req.setComments('Discount needed to beat competitor pricing');
        Approval.ProcessResult result;
        System.runAs(SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.REP_LAST_NAME)) {
            result = Approval.process(req);
        }
        return result;
    }

    private static ProcessInstanceWorkitem pendingWorkitem(Id oppId) {
        return [
            SELECT Id, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :oppId AND ProcessInstance.Status = 'Pending'
            LIMIT 1
        ];
    }

    private static void decide(Id oppId, String action) {
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setWorkitemId(pendingWorkitem(oppId).Id);
        req.setAction(action);
        Approval.process(req);
    }

    private static String status(Id oppId) {
        return [SELECT Discount_Approval_Status__c FROM Opportunity WHERE Id = :oppId].Discount_Approval_Status__c;
    }

    @IsTest
    static void tierOneRoutesToManagerAndApproves() {
        Opportunity opp = createRepOpp(15);
        User manager = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.MANAGER_LAST_NAME);

        Test.startTest();
        Assert.isTrue(submitAsOwner(opp.Id).isSuccess());
        Assert.areEqual(OpportunityService.STATUS_PENDING, status(opp.Id));
        Assert.areEqual(manager.Id, pendingWorkitem(opp.Id).ActorId, 'Tier 1 goes to the owner\'s manager');

        decide(opp.Id, 'Approve');
        Test.stopTest();

        Assert.areEqual(OpportunityService.STATUS_APPROVED, status(opp.Id), 'Tier 1 is a single-step approval');
    }

    @IsTest
    static void tierTwoAddsExecutiveStep() {
        Opportunity opp = createRepOpp(30);
        User exec = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.EXEC_LAST_NAME);

        Test.startTest();
        submitAsOwner(opp.Id);
        decide(opp.Id, 'Approve');
        Assert.areEqual(OpportunityService.STATUS_PENDING, status(opp.Id), 'Still pending executive review');
        Assert.areEqual(exec.Id, pendingWorkitem(opp.Id).ActorId, 'Tier 2 escalates to the executive approver');

        decide(opp.Id, 'Approve');
        Test.stopTest();

        Assert.areEqual(OpportunityService.STATUS_APPROVED, status(opp.Id));
    }

    @IsTest
    static void rejectionAllowsResubmission() {
        Opportunity opp = createRepOpp(15);

        Test.startTest();
        submitAsOwner(opp.Id);
        decide(opp.Id, 'Reject');
        Assert.areEqual(OpportunityService.STATUS_REJECTED, status(opp.Id));

        Assert.isTrue(submitAsOwner(opp.Id).isSuccess(), 'Rejected requests can be resubmitted');
        Test.stopTest();
    }

    @IsTest
    static void discountsWithinPolicyCannotBeSubmitted() {
        Opportunity opp = createRepOpp(5);
        try {
            submitAsOwner(opp.Id);
            Assert.fail('Expected NO_APPLICABLE_PROCESS');
        } catch (DmlException ex) {
            Assert.areEqual(StatusCode.NO_APPLICABLE_PROCESS, ex.getDmlType(0));
        }
    }
}
