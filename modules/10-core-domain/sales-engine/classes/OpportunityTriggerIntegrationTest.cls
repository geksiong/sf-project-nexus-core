/**
 * @description Database-level tests for the Opportunity trigger wiring: the handler routes insert and
 * update to OpportunityService, logic is bulk-safe at 200 records, and the bypass framework applies.
 * Rule-by-rule behaviour is covered in memory by OpportunityServiceTest.
 */
@IsTest
private class OpportunityTriggerIntegrationTest {
    private static Opportunity reload(Id oppId) {
        return [
            SELECT Id, StageName, Approval_Tier__c, Discount_Approval_Status__c
            FROM Opportunity
            WHERE Id = :oppId
        ];
    }

    @IsTest
    static void triggerAppliesDiscountPolicyOnInsertAndUpdate() {
        SalesEngineTestFixtures.useStandardTiers();
        Opportunity opp = TestDataFactory.createOpportunities(
            TestDataFactory.createAccounts(1, true)[0].Id,
            1,
            false
        )[0];
        opp.Discount_Percentage__c = 15;

        insert opp;
        Assert.areEqual('Tier 1', reload(opp.Id).Approval_Tier__c, 'before insert routes to OpportunityService');

        opp.Discount_Percentage__c = 5;
        update opp;
        Opportunity saved = reload(opp.Id);
        Assert.isNull(saved.Approval_Tier__c, 'before update routes to OpportunityService');
        Assert.areEqual(OpportunityService.STATUS_NOT_REQUIRED, saved.Discount_Approval_Status__c);
    }

    @IsTest
    static void bulkInsertAndUpdateOf200StaysWithinLimits() {
        SalesEngineTestFixtures.useStandardTiers();
        List<Opportunity> opps = TestDataFactory.createOpportunities(
            TestDataFactory.createAccounts(1, true)[0].Id,
            200,
            false
        );
        for (Integer i = 0; i < opps.size(); i++) {
            opps[i].Discount_Percentage__c = Math.mod(i, 40);
        }

        Test.startTest();
        insert opps;
        for (Opportunity opp : opps) {
            opp.StageName = OpportunityService.STAGE_CLOSED_LOST;
            opp.Loss_Reason__c = 'Price';
        }
        update opps;
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Opportunity WHERE StageName = :OpportunityService.STAGE_CLOSED_LOST]);
        Assert.areEqual(
            70,
            [SELECT COUNT() FROM Opportunity WHERE Approval_Tier__c = 'Tier 2'],
            'Discounts 26-39 of every 40'
        );
        Assert.isTrue(queriesUsed < 10, 'Trigger logic must be bulkified, used ' + queriesUsed + ' queries');
    }

    @IsTest
    static void bypassSkipsAllOpportunityRules() {
        Account creditHold = TestDataFactory.createAccounts(1, false)[0];
        creditHold.Credit_Hold__c = true;
        insert creditHold;
        BypassService.setTriggerBypass('Opportunity', true);

        Opportunity opp = TestDataFactory.createOpportunities(creditHold.Id, 1, false)[0];
        opp.Discount_Percentage__c = 50;
        opp.StageName = OpportunityService.STAGE_CLOSED_WON;
        insert opp;

        Opportunity saved = reload(opp.Id);
        Assert.areEqual(OpportunityService.STAGE_CLOSED_WON, saved.StageName, 'Stage gates bypassed');
        Assert.isNull(saved.Approval_Tier__c, 'Discount policy bypassed');
    }
}
