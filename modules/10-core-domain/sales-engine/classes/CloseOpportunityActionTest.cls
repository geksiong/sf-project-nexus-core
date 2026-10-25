@IsTest
private class CloseOpportunityActionTest {
    @TestSetup
    static void setup() {
        SalesEngineTestFixtures.createManagerChain();
        Account acc = TestDataFactory.createAccounts(1, true)[0];
        TestDataFactory.createContacts(acc.Id, 2, true);
        TestDataFactory.createOpportunities(acc.Id, 2, true);
    }

    private static CloseOpportunityAction.Request request(Id oppId, String outcome, Id contactId, String lossReason) {
        CloseOpportunityAction.Request req = new CloseOpportunityAction.Request();
        req.opportunityId = oppId;
        req.outcome = outcome;
        req.primaryContactId = contactId;
        req.lossReason = lossReason;
        return req;
    }

    private static CloseOpportunityAction.Request requestWithRawContact(Id oppId, String rawContactId) {
        CloseOpportunityAction.Request req = request(oppId, 'Won', null, null);
        req.primaryContactId = rawContactId;
        return req;
    }

    private static CloseOpportunityAction.Result executeOne(CloseOpportunityAction.Request req) {
        return CloseOpportunityAction.execute(new List<CloseOpportunityAction.Request>{ req })[0];
    }

    @IsTest
    static void wonAssignsPrimaryContactAndCloses() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
            Contact c = [SELECT Id FROM Contact LIMIT 1];

            Test.startTest();
            CloseOpportunityAction.Result result = executeOne(request(opp.Id, 'Won', c.Id, null));
            Test.stopTest();

            Assert.isTrue(result.isSuccess, JSON.serialize(result));
            Assert.areEqual('Closed Won', result.payload.stageName);
            Assert.areEqual(opp.Id, result.payload.opportunityId);
            OpportunityContactRole ocr = [
                SELECT IsPrimary, Role
                FROM OpportunityContactRole
                WHERE OpportunityId = :opp.Id
            ];
            Assert.isTrue(ocr.IsPrimary);
            Assert.areEqual('Decision Maker', ocr.Role);
        }
    }

    @IsTest
    static void wonPromotesExistingContactRoleToPrimary() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
            Contact c = [SELECT Id FROM Contact LIMIT 1];
            insert new OpportunityContactRole(
                OpportunityId = opp.Id,
                ContactId = c.Id,
                IsPrimary = false,
                Role = 'Influencer'
            );

            CloseOpportunityAction.Result result = executeOne(request(opp.Id, 'Won', c.Id, null));

            Assert.isTrue(result.isSuccess, JSON.serialize(result));
            OpportunityContactRole ocr = [
                SELECT IsPrimary, Role
                FROM OpportunityContactRole
                WHERE OpportunityId = :opp.Id
            ];
            Assert.isTrue(ocr.IsPrimary);
            Assert.areEqual('Influencer', ocr.Role, 'Existing role is kept');
        }
    }

    @IsTest
    static void wonWithExistingPrimaryNeedsNoContact() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
            Contact c = [SELECT Id FROM Contact LIMIT 1];
            insert new OpportunityContactRole(OpportunityId = opp.Id, ContactId = c.Id, IsPrimary = true);

            Assert.isTrue(executeOne(request(opp.Id, 'Won', c.Id, null)).isSuccess);
        }
    }

    @IsTest
    static void stageGateFailureReturnsDmlError() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

            CloseOpportunityAction.Result result = executeOne(request(opp.Id, 'Won', null, null));

            Assert.isFalse(result.isSuccess);
            Assert.areEqual(OpportunityService.ERROR_DML, result.errorCode);
            Assert.isTrue(result.errorMessage.contains('Primary Contact Role'), JSON.serialize(result));
            Assert.isNull(result.payload);
        }
    }

    @IsTest
    static void lostRecordsReason() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

            CloseOpportunityAction.Result result = executeOne(request(opp.Id, 'Lost', null, 'Competitor'));

            Assert.isTrue(result.isSuccess, JSON.serialize(result));
            Opportunity saved = [SELECT StageName, Loss_Reason__c FROM Opportunity WHERE Id = :opp.Id];
            Assert.areEqual('Closed Lost', saved.StageName);
            Assert.areEqual('Competitor', saved.Loss_Reason__c);
        }
    }

    @IsTest
    static void invalidInputsAreRejectedPerRequest() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            List<Opportunity> opps = [SELECT Id FROM Opportunity LIMIT 2];
            Account acc = [SELECT Id FROM Account LIMIT 1];

            List<CloseOpportunityAction.Request> requests = new List<CloseOpportunityAction.Request>{
                request(null, 'Won', null, null),
                request(acc.Id, 'Won', null, null),
                request(opps[0].Id, 'Maybe', null, null),
                request(opps[0].Id, 'Lost', null, ''),
                request(opps[0].Id, 'Won', acc.Id, null),
                requestWithRawContact(opps[0].Id, 'not-an-id'),
                request(opps[1].Id, 'Lost', null, 'Price'),
                request(opps[1].Id, 'Lost', null, 'Price')
            };
            List<CloseOpportunityAction.Result> results = CloseOpportunityAction.execute(requests);

            for (Integer i = 0; i < 6; i++) {
                Assert.isFalse(results[i].isSuccess, 'Request ' + i + ' should fail');
                Assert.areEqual(OpportunityService.ERROR_INVALID_INPUT, results[i].errorCode, 'Request ' + i);
            }
            Assert.isTrue(results[6].isSuccess, 'Valid request in the same batch still succeeds');
            Assert.isTrue(results[7].errorMessage.contains('Duplicate'));
        }
    }

    @IsTest
    static void unknownOpportunityIsNotFound() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Id fakeOppId = TestDataFactory.getFakeId(Opportunity.SObjectType);
            CloseOpportunityAction.Result result = executeOne(request(fakeOppId, 'Lost', null, 'Price'));
            Assert.areEqual(OpportunityService.ERROR_NOT_FOUND, result.errorCode);
        }
    }

    @IsTest
    static void contactRoleFailureSkipsStageUpdate() {
        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
            Id fakeContactId = TestDataFactory.getFakeId(Contact.SObjectType);

            CloseOpportunityAction.Result result = executeOne(request(opp.Id, 'Won', fakeContactId, null));

            Assert.areEqual(OpportunityService.ERROR_DML, result.errorCode);
            Assert.isTrue(result.errorMessage.startsWith('Could not assign primary contact'), JSON.serialize(result));
            Assert.areNotEqual('Closed Won', [SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName);
        }
    }

    @IsTest
    static void expectedRejectionsLogWarnSystemFailuresLogError() {
        List<Opportunity> opps = [SELECT Id FROM Opportunity LIMIT 2];
        Id fakeContactId = TestDataFactory.getFakeId(Contact.SObjectType);

        System.runAs(SalesEngineTestFixtures.salesAdmin()) {
            Test.startTest();
            // Stage gate (no primary contact) is an expected business rejection.
            executeOne(request(opps[0].Id, 'Won', null, null));
            // A contact role that cannot be saved is an unexpected system failure.
            executeOne(request(opps[1].Id, 'Won', fakeContactId, null));
            Test.stopTest();
        }

        Map<String, String> levelByCode = new Map<String, String>();
        for (LogEntry__c entry : [SELECT LoggingLevel__c, Message__c FROM LogEntry__c]) {
            if (!entry.Message__c.startsWith('CloseOpportunityAction')) {
                continue; // Message__c is long text and cannot be filtered in SOQL
            }
            levelByCode.put(
                entry.Message__c.contains('Could not assign primary contact') ? 'contact' : 'gate',
                entry.LoggingLevel__c
            );
        }
        Assert.areEqual('WARN', levelByCode.get('gate'), 'Stage gate rejections are expected: ' + levelByCode);
        Assert.areEqual('ERROR', levelByCode.get('contact'), 'Unexpected DML failures stay ERROR: ' + levelByCode);
    }

    @IsTest
    static void salesRepWithPsgCanCloseDealsInUserMode() {
        User rep = SalesEngineTestFixtures.getUser(SalesEngineTestFixtures.REP_LAST_NAME);
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        opp.OwnerId = rep.Id;
        update opp;

        CloseOpportunityAction.Result result;
        System.runAs(rep) {
            result = executeOne(request(opp.Id, 'Won', c.Id, null));
        }
        Assert.areEqual(true, result.isSuccess, JSON.serialize(result));
    }
}
