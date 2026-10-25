@IsTest
private class RetryLedgerPostingActionTest {
    @TestSetup
    static void setup() {
        CapExTestFixtures.createUsers();
    }

    /** @description An approved request whose posting has failed (built without the event pipeline). */
    private static CapEx_Request__c failedPosting() {
        CapEx_Request__c request = CapExTestFixtures.newRequest(
            CapExTestFixtures.getUser(CapExTestFixtures.REP).Id,
            6400
        );
        insert request;
        BypassService.setTriggerBypass('CapEx_Request__c', true);
        update new CapEx_Request__c(
            Id = request.Id,
            Status__c = CapExService.STATUS_APPROVED,
            Ledger_Status__c = LedgerPostingService.LEDGER_FAILED
        );
        BypassService.setTriggerBypass('CapEx_Request__c', false);
        insert new Ledger_Entry__c(
            CapEx_Request__c = request.Id,
            Idempotency_Key__c = request.Id,
            Amount__c = 6400,
            Status__c = LedgerPostingService.ENTRY_FAILED,
            Attempts__c = 3,
            Last_Error__c = 'ERP HTTP 503'
        );
        return request;
    }

    private static RetryLedgerPostingAction.Request request(Id requestId) {
        RetryLedgerPostingAction.Request req = new RetryLedgerPostingAction.Request();
        req.capexRequestId = requestId;
        return req;
    }

    private static List<RetryLedgerPostingAction.Result> retryAs(String lastName, List<Id> requestIds) {
        List<RetryLedgerPostingAction.Request> requests = new List<RetryLedgerPostingAction.Request>();
        for (Id requestId : requestIds) {
            requests.add(request(requestId));
        }
        List<RetryLedgerPostingAction.Result> results;
        System.runAs(CapExTestFixtures.getUser(lastName)) {
            results = RetryLedgerPostingAction.execute(requests);
        }
        return results;
    }

    @IsTest
    static void opsAdminRequeuesAFailedPosting() {
        ErpLedgerMock.install();
        CapEx_Request__c request = failedPosting();

        Test.startTest();
        List<RetryLedgerPostingAction.Result> results = retryAs(
            CapExTestFixtures.OPS_ADMIN,
            new List<Id>{ request.Id }
        );
        Assert.isTrue(results[0].isSuccess, String.valueOf(results[0]));
        Assert.areEqual(LedgerPostingService.LEDGER_PENDING, results[0].payload.ledgerStatus);
        Test.stopTest();

        Ledger_Entry__c entry = CapExTestFixtures.ledgerEntry(request.Id);
        Assert.areEqual(
            LedgerPostingService.ENTRY_POSTED,
            entry.Status__c,
            String.valueOf(entry) + LedgerPostingJob.deferredInTests
        );
        Assert.areEqual(1, entry.Attempts__c, 'Attempts restart from zero');
        Assert.areEqual(
            LedgerPostingService.LEDGER_POSTED,
            [SELECT Ledger_Status__c FROM CapEx_Request__c WHERE Id = :request.Id].Ledger_Status__c
        );
    }

    @IsTest
    static void invalidStateAndMissingRequestsAreRejected() {
        CapEx_Request__c draft = CapExTestFixtures.newRequest(CapExTestFixtures.getUser(CapExTestFixtures.REP).Id, 10);
        insert draft;
        Id missing = TestDataFactory.getFakeId(CapEx_Request__c.SObjectType);
        Id wrongType = TestDataFactory.getFakeId(Account.SObjectType);

        List<RetryLedgerPostingAction.Result> results = retryAs(
            CapExTestFixtures.OPS_ADMIN,
            new List<Id>{ draft.Id, missing, wrongType, null, draft.Id }
        );

        Assert.areEqual(LedgerPostingService.ERROR_INVALID_STATE, results[0].errorCode, String.valueOf(results[0]));
        Assert.areEqual(LedgerPostingService.ERROR_NOT_FOUND, results[1].errorCode);
        Assert.areEqual(LedgerPostingService.ERROR_INVALID_INPUT, results[2].errorCode);
        Assert.areEqual(LedgerPostingService.ERROR_INVALID_INPUT, results[3].errorCode);
        Assert.areEqual(LedgerPostingService.ERROR_INVALID_INPUT, results[4].errorCode, 'Duplicate');
    }

    /** @description The submitter can see the request but may not edit its ledger status. */
    @IsTest
    static void usersWithoutLedgerAccessCannotRetry() {
        CapEx_Request__c request = failedPosting();

        List<RetryLedgerPostingAction.Result> results = retryAs(CapExTestFixtures.REP, new List<Id>{ request.Id });

        Assert.isFalse(results[0].isSuccess, String.valueOf(results[0]));
        Assert.areEqual(LedgerPostingService.ERROR_DML, results[0].errorCode, String.valueOf(results[0]));
        Assert.areEqual(LedgerPostingService.ENTRY_FAILED, CapExTestFixtures.ledgerEntry(request.Id).Status__c);
    }
}
