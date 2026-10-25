@IsTest
private class OpportunityServiceTest {
    @TestSetup
    static void setup() {
        SalesEngineTestFixtures.createManagerChain();
        List<Account> accounts = TestDataFactory.createAccounts(2, false);
        accounts[1].Credit_Hold__c = true;
        insert accounts;
        TestDataFactory.createContacts(accounts[0].Id, 1, true);
    }

    private static Account goodAccount() {
        return [SELECT Id FROM Account WHERE Credit_Hold__c = false LIMIT 1];
    }

    private static Account creditHoldAccount() {
        return [SELECT Id FROM Account WHERE Credit_Hold__c = true LIMIT 1];
    }

    private static Opportunity newOpp(Id accountId, Decimal discount) {
        Opportunity opp = TestDataFactory.createOpportunities(accountId, 1, false)[0];
        opp.Discount_Percentage__c = discount;
        return opp;
    }

    private static Opportunity reload(Id oppId) {
        return [
            SELECT Id, StageName, Approval_Tier__c, Discount_Approval_Status__c, Executive_Approver__c, Discount_Percentage__c
            FROM Opportunity
            WHERE Id = :oppId
        ];
    }

    private static String saveError(SObject record, Boolean isInsert) {
        Database.SaveResult result = isInsert ? Database.insert(record, false) : Database.update(record, false);
        Assert.isFalse(result.isSuccess(), 'Expected the save to be rejected');
        List<String> messages = new List<String>();
        for (Database.Error err : result.getErrors()) {
            messages.add(err.getMessage());
        }
        return String.join(messages, ' | ');
    }

    @IsTest
    static void derivesTierAndStatusFromDiscount() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            SalesEngineTestFixtures.useStandardTiers();
            User rep = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.REP_LAST_NAME);
            User exec = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.EXEC_LAST_NAME);
            Id accountId = goodAccount().Id;

            List<Opportunity> opps = new List<Opportunity>{
                newOpp(accountId, null),
                newOpp(accountId, 10),
                newOpp(accountId, 15),
                newOpp(accountId, 30)
            };
            for (Opportunity opp : opps) {
                opp.OwnerId = rep.Id;
            }
            insert opps;

            Opportunity noDiscount = reload(opps[0].Id);
            Assert.isNull(noDiscount.Approval_Tier__c);
            Assert.areEqual(OpportunityService.STATUS_NOT_REQUIRED, noDiscount.Discount_Approval_Status__c);

            Assert.isNull(reload(opps[1].Id).Approval_Tier__c, 'Threshold is exclusive: 10% needs no approval');

            Opportunity tier1 = reload(opps[2].Id);
            Assert.areEqual('Tier 1', tier1.Approval_Tier__c);
            Assert.areEqual(OpportunityService.STATUS_NOT_SUBMITTED, tier1.Discount_Approval_Status__c);
            Assert.isNull(tier1.Executive_Approver__c);

            Opportunity tier2 = reload(opps[3].Id);
            Assert.areEqual('Tier 2', tier2.Approval_Tier__c);
            Assert.areEqual(exec.Id, tier2.Executive_Approver__c, 'Executive approver is the owner\'s manager\'s manager');
        }
    }

    @IsTest
    static void rejectsOutOfRangeDiscount() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            String message = saveError(newOpp(goodAccount().Id, 120), true);
            Assert.isTrue(message.contains('between 0% and 100%'), message);
        }
    }

    @IsTest
    static void loweringApprovedDiscountKeepsApprovalRaisingResets() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            SalesEngineTestFixtures.useStandardTiers();
            Opportunity opp = newOpp(goodAccount().Id, 20);
            insert opp;
            opp.Discount_Approval_Status__c = OpportunityService.STATUS_APPROVED;
            update opp;

            opp.Discount_Percentage__c = 12;
            update opp;
            Assert.areEqual(OpportunityService.STATUS_APPROVED, reload(opp.Id).Discount_Approval_Status__c);

            opp.Discount_Percentage__c = 18;
            update opp;
            Assert.areEqual(OpportunityService.STATUS_NOT_SUBMITTED, reload(opp.Id).Discount_Approval_Status__c);

            opp.Discount_Percentage__c = 5;
            update opp;
            Opportunity cleared = reload(opp.Id);
            Assert.isNull(cleared.Approval_Tier__c);
            Assert.areEqual(OpportunityService.STATUS_NOT_REQUIRED, cleared.Discount_Approval_Status__c);
        }
    }

    @IsTest
    static void blocksDiscountChangeWhilePending() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            SalesEngineTestFixtures.useStandardTiers();
            Opportunity opp = newOpp(goodAccount().Id, 20);
            insert opp;
            opp.Discount_Approval_Status__c = OpportunityService.STATUS_PENDING;
            update opp;

            opp.Discount_Percentage__c = 22;
            Assert.isTrue(saveError(opp, false).contains('approval is pending'));
        }
    }

    @IsTest
    static void ownerChangeRecalculatesExecutiveApprover() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            SalesEngineTestFixtures.useStandardTiers();
            User rep = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.REP_LAST_NAME);
            User manager = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.MANAGER_LAST_NAME);
            User exec = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.EXEC_LAST_NAME);

            Opportunity opp = newOpp(goodAccount().Id, 30);
            opp.OwnerId = rep.Id;
            insert opp;
            Assert.areEqual(exec.Id, reload(opp.Id).Executive_Approver__c);

            // Manager's chain has only one level above: falls back to the owner's manager (exec).
            opp.OwnerId = manager.Id;
            update opp;
            Assert.areEqual(exec.Id, reload(opp.Id).Executive_Approver__c);

            // Exec has no manager at all: no executive approver can be resolved.
            opp.OwnerId = exec.Id;
            update opp;
            Assert.isNull(reload(opp.Id).Executive_Approver__c);

            // Dropping to Tier 1 clears the executive approver.
            opp.OwnerId = rep.Id;
            opp.Discount_Percentage__c = 15;
            update opp;
            Assert.isNull(reload(opp.Id).Executive_Approver__c);
        }
    }

    @IsTest
    static void creditHoldBlocksClosedWonOnInsertAndUpdate() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity onInsert = newOpp(creditHoldAccount().Id, null);
            onInsert.StageName = OpportunityService.STAGE_CLOSED_WON;
            Assert.isTrue(saveError(onInsert, true).contains('Credit Hold'));

            Opportunity onUpdate = newOpp(creditHoldAccount().Id, null);
            insert onUpdate;
            onUpdate.StageName = OpportunityService.STAGE_CLOSED_WON;
            Assert.isTrue(saveError(onUpdate, false).contains('Credit Hold'));
        }
    }

    @IsTest
    static void unapprovedDiscountBlocksClosedWon() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            SalesEngineTestFixtures.useStandardTiers();
            Opportunity opp = newOpp(goodAccount().Id, 15);
            insert opp;
            opp.StageName = OpportunityService.STAGE_CLOSED_WON;
            String message = saveError(opp, false);
            Assert.isTrue(message.contains('Tier 1 approval'), message);
        }
    }

    @IsTest
    static void primaryContactRoleRequiredToCloseWonOnUpdate() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = newOpp(goodAccount().Id, null);
            insert opp;
            opp.StageName = OpportunityService.STAGE_CLOSED_WON;
            Assert.isTrue(saveError(opp, false).contains('Primary Contact Role'));

            Contact c = [SELECT Id FROM Contact LIMIT 1];
            insert new OpportunityContactRole(OpportunityId = opp.Id, ContactId = c.Id, IsPrimary = true, Role = 'Decision Maker');
            update opp;
            Assert.areEqual(OpportunityService.STAGE_CLOSED_WON, reload(opp.Id).StageName);
        }
    }

    @IsTest
    static void closedWonInsertAllowedForMigratedDeals() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = newOpp(goodAccount().Id, null);
            opp.StageName = OpportunityService.STAGE_CLOSED_WON;
            insert opp;
            Assert.areEqual(OpportunityService.STAGE_CLOSED_WON, reload(opp.Id).StageName);
        }
    }

    @IsTest
    static void lossReasonRequiredForClosedLost() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = newOpp(goodAccount().Id, null);
            insert opp;
            opp.StageName = OpportunityService.STAGE_CLOSED_LOST;
            Assert.isTrue(saveError(opp, false).contains('Loss Reason'));

            opp.Loss_Reason__c = 'Competitor';
            update opp;
            Assert.areEqual(OpportunityService.STAGE_CLOSED_LOST, reload(opp.Id).StageName);
        }
    }

    @IsTest
    static void bulkInsertOf200StaysWithinLimits() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            SalesEngineTestFixtures.useStandardTiers();
            List<Opportunity> opps = TestDataFactory.createOpportunities(goodAccount().Id, 200, false);
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
            Assert.isTrue(queriesUsed < 10, 'Trigger logic must be bulkified, used ' + queriesUsed + ' queries');
        }
    }

    @IsTest
    static void bypassSkipsAllOpportunityRules() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            BypassService.setTriggerBypass('Opportunity', true);
            Opportunity opp = newOpp(creditHoldAccount().Id, 50);
            opp.StageName = OpportunityService.STAGE_CLOSED_WON;
            insert opp;
            Assert.isNull(reload(opp.Id).Approval_Tier__c, 'Bypassed trigger must not derive approval fields');
        }
    }

    @IsTest
    static void tiersLoadFromCustomMetadataSortedByThreshold() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            OpportunityService.approvalTiers = new List<Discount_Approval_Tier__mdt>{
                new Discount_Approval_Tier__mdt(Discount_Threshold__c = 5, Approval_Tier__c = 'Tier 1'),
                new Discount_Approval_Tier__mdt(Discount_Threshold__c = 40, Approval_Tier__c = 'Tier 2')
            };
            Assert.areEqual('Tier 2', OpportunityService.resolveTier(41));
            Assert.areEqual('Tier 1', OpportunityService.resolveTier(6));
            Assert.isNull(OpportunityService.resolveTier(5));

            OpportunityService.approvalTiers = null;
            Assert.isNotNull(OpportunityService.approvalTiers, 'Lazily reloads deployed Discount_Approval_Tier__mdt');
        }
    }
}
