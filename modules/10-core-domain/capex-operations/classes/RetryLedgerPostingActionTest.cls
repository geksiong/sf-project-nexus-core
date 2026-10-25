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

    /** @description Approved and marked Pending, but no ledger entry: the event was lost. */
    private static CapEx_Request__c stuckApproval(Integer minutesAgo) {
        CapEx_Request__c request = CapExTestFixtures.newRequest(
            CapExTestFixtures.getUser(CapExTestFixtures.REP).Id,
            5200
        );
        insert request;
        BypassService.setTriggerBypass('CapEx_Request__c', true);
        update new CapEx_Request__c(
            Id = request.Id,
            Status__c = CapExService.STATUS_APPROVED,
            Ledger_Status__c = LedgerPostingService.LEDGER_PENDING,
            Approved_On__c = System.now().addMinutes(-minutesAgo)
        );
        BypassService.setTriggerBypass('CapEx_Request__c', false);
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
    static void opsAdminRecoversAnApprovalWhoseEventWasLost() {
        ErpLedgerMock.install();
        CapEx_Request__c request = stuckApproval(30);

        Test.startTest();
        List<RetryLedgerPostingAction.Result> results = retryAs(
            CapExTestFixtures.OPS_ADMIN,
            new List<Id>{ request.Id }
        );
        Assert.isTrue(results[0].isSuccess, String.valueOf(results[0]));
        Test.stopTest();

        Ledger_Entry__c entry = CapExTestFixtures.ledgerEntry(request.Id);
        Assert.areEqual(LedgerPostingService.ENTRY_POSTED, entry.Status__c, String.valueOf(entry));
        Assert.areEqual(5200, entry.Amount__c, 'Recovered from the approved request itself');
    }

    @IsTest
    static void recentOrInProgressPendingPostingsAreLeftAlone() {
        CapEx_Request__c recent = stuckApproval(1);
        CapEx_Request__c inProgress = stuckApproval(30);
        insert new Ledger_Entry__c(CapEx_Request__c = inProgress.Id, Idempotency_Key__c = inProgress.Id);

        List<RetryLedgerPostingAction.Result> results = retryAs(
            CapExTestFixtures.OPS_ADMIN,
            new List<Id>{ recent.Id, inProgress.Id }
        );

        Assert.areEqual(LedgerPostingService.ERROR_INVALID_STATE, results[0].errorCode);
        Assert.isTrue(results[0].errorMessage.contains('less than'), results[0].errorMessage);
        Assert.areEqual(LedgerPostingService.ERROR_INVALID_STATE, results[1].errorCode);
        Assert.isTrue(results[1].errorMessage.contains('being posted'), results[1].errorMessage);
        Assert.areEqual(1, [SELECT COUNT() FROM Ledger_Entry__c], 'No entry was created for the recent approval');
    }

    /**
     * @description Approved requests are locked by the approval process. The ops admin (Modify All on
     * CapEx) can still retry, and the posting job, running as that user, can update the locked request.
     */
    @IsTest
    static void retryWorksOnRequestsLockedByTheApprovalProcess() {
        ErpLedgerMock mock = ErpLedgerMock.install();
        mock.statusCode = 503;
        LedgerPostingService.maxAttemptsOverride = 1;
        CapEx_Request__c request = CapExTestFixtures.newRequest(
            CapExTestFixtures.getUser(CapExTestFixtures.REP).Id,
            7300
        );
        insert request;
        Test.startTest();
        CapExTestFixtures.submitAndDecide(request.Id, 'Approve');
        Test.getEventBus().deliver();
        Test.stopTest();
        // CapEx Approval has finalApprovalRecordLock = true (Approval.isLocked needs an org preference).
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :request.Id AND Status = 'Approved'],
            'Approved by the real process, so the request is locked'
        );
        Assert.areEqual(LedgerPostingService.ENTRY_FAILED, CapExTestFixtures.ledgerEntry(request.Id).Status__c);

        mock.statusCode = 201;
        System.runAs(CapExTestFixtures.getUser(CapExTestFixtures.OPS_ADMIN)) {
            List<RetryLedgerPostingAction.Result> results = RetryLedgerPostingAction.execute(
                new List<RetryLedgerPostingAction.Request>{ request(request.Id) }
            );
            Assert.isTrue(results[0].isSuccess, String.valueOf(results[0]));
            Assert.areEqual(LedgerPostingService.ENTRY_PENDING, CapExTestFixtures.ledgerEntry(request.Id).Status__c);
            // The job it queued, run inline as the same user (tests run queued jobs only at stopTest). Inline,
            // it shares this transaction's uncommitted DML, which forbids callouts: simulate the ERP here.
            ErpLedgerClient.simulateOverride = true;
            new LedgerPostingJob(new Set<Id>{ CapExTestFixtures.ledgerEntry(request.Id).Id }).execute(null);
        }

        Assert.areEqual(LedgerPostingService.ENTRY_POSTED, CapExTestFixtures.ledgerEntry(request.Id).Status__c);
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
