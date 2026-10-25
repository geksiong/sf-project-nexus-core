/**
 * @description In-memory unit tests for ledger planning (idempotency) and posting outcomes (retry, fail).
 */
@IsTest
private class LedgerPostingServiceTest {
    private static final Id REQUEST_A = TestDataFactory.getFakeId(CapEx_Request__c.SObjectType);
    private static final Id REQUEST_B = TestDataFactory.getFakeId(CapEx_Request__c.SObjectType);

    private static TestStub facts;

    private static void mockFacts(Map<String, Id> existingKeys) {
        facts = new TestStub().returns('selectLedgerEntryIdsByKey', existingKeys);
        CapExFactsSelector.instance = (CapExFactsSelector) facts.create(CapExFactsSelector.class);
    }

    private static CapEx_Approved__e event(String requestId, Decimal amount) {
        return new CapEx_Approved__e(
            CapEx_Request_Id__c = requestId,
            Amount__c = amount,
            Department__c = 'Customer Care'
        );
    }

    private static Ledger_Entry__c pending(Id requestId, Integer attempts) {
        return new Ledger_Entry__c(
            Id = TestDataFactory.getFakeId(Ledger_Entry__c.SObjectType),
            CapEx_Request__c = requestId,
            Idempotency_Key__c = requestId,
            Attempts__c = attempts
        );
    }

    @IsTest
    static void oneEntryPerRequestSkippingDuplicatesAndExistingEntries() {
        mockFacts(
            new Map<String, Id>{ String.valueOf(REQUEST_B) => TestDataFactory.getFakeId(Ledger_Entry__c.SObjectType) }
        );

        List<Ledger_Entry__c> entries = LedgerPostingService.planLedgerEntries(
            new List<CapEx_Approved__e>{
                event(REQUEST_A, 100),
                event(REQUEST_A, 100),
                event(REQUEST_B, 200),
                event('not-an-id', 300)
            }
        );

        Assert.areEqual(1, entries.size(), 'Duplicate, already-booked and invalid events create nothing');
        Assert.areEqual(REQUEST_A, entries[0].CapEx_Request__c);
        Assert.areEqual(String.valueOf(REQUEST_A), entries[0].Idempotency_Key__c);
        Assert.areEqual(LedgerPostingService.ENTRY_PENDING, entries[0].Status__c);
        Assert.areEqual(100, entries[0].Amount__c);
        Assert.isTrue(Logger.getBufferSize() > 0, 'The invalid event is logged');
    }

    @IsTest
    static void successPostsTheEntryAndTheRequest() {
        Ledger_Entry__c entry = pending(REQUEST_A, 0);
        LedgerPostingService.PostingOutcome outcome = LedgerPostingService.applyPostingResults(
            new List<Ledger_Entry__c>{ entry },
            new Map<String, ErpLedgerClient.PostResult>{
                entry.Idempotency_Key__c => new ErpLedgerClient.PostResult(true, 'ERP-1', null)
            },
            3
        );

        Assert.areEqual(LedgerPostingService.ENTRY_POSTED, outcome.entries[0].Status__c);
        Assert.areEqual('ERP-1', outcome.entries[0].ERP_Reference__c);
        Assert.isNotNull(outcome.entries[0].Posted_On__c);
        Assert.areEqual(1, outcome.entries[0].Attempts__c);
        Assert.areEqual(LedgerPostingService.LEDGER_POSTED, outcome.requests[0].Ledger_Status__c);
        Assert.isTrue(outcome.retryIds.isEmpty());
    }

    @IsTest
    static void failuresRetryUntilTheLastAttemptThenFail() {
        Ledger_Entry__c early = pending(REQUEST_A, 0);
        Ledger_Entry__c last = pending(REQUEST_B, 2);
        LedgerPostingService.PostingOutcome outcome = LedgerPostingService.applyPostingResults(
            new List<Ledger_Entry__c>{ early, last },
            new Map<String, ErpLedgerClient.PostResult>{
                early.Idempotency_Key__c => new ErpLedgerClient.PostResult(false, null, 'ERP HTTP 503')
            },
            3
        );

        Assert.areEqual(new Set<Id>{ early.Id }, outcome.retryIds, 'Attempt 1 of 3 is retried');
        Assert.isNull(outcome.entries[0].Status__c, 'Still Pending');
        Assert.areEqual('ERP HTTP 503', outcome.entries[0].Last_Error__c);
        Assert.areEqual(LedgerPostingService.ENTRY_FAILED, outcome.entries[1].Status__c, 'Attempt 3 of 3 fails');
        Assert.areEqual('No ERP result.', outcome.entries[1].Last_Error__c);
        Assert.areEqual(1, outcome.finalFailures.size());
        Assert.areEqual(1, outcome.requests.size());
        Assert.areEqual(LedgerPostingService.LEDGER_FAILED, outcome.requests[0].Ledger_Status__c);
        Assert.areEqual(3, outcome.highestAttempt);
    }

    @IsTest
    static void retryDelaysGrowAndAttemptsComeFromSettings() {
        Assert.areEqual(1, LedgerPostingService.retryDelay(1));
        Assert.areEqual(5, LedgerPostingService.retryDelay(2));
        Assert.areEqual(30, LedgerPostingService.retryDelay(9), 'Capped at the longest delay');
        Assert.areEqual(3, LedgerPostingService.maxAttempts(), 'ERP_Ledger_Setting.Default');
        LedgerPostingService.maxAttemptsOverride = 1;
        Assert.areEqual(1, LedgerPostingService.maxAttempts());
    }
}
