/**
 * @description End-to-end CapEx flow against the database: approval process -> CapEx_Approved__e ->
 * ledger consumer -> ERP posting job, plus idempotency, ERP outage, Private OWD sharing, bulk and bypass.
 */
@IsTest
private class CapExLifecycleIntegrationTest {
    @TestSetup
    static void setup() {
        CapExTestFixtures.createUsers();
    }

    private static CapEx_Request__c insertDraft(Decimal amount) {
        CapEx_Request__c request = CapExTestFixtures.newRequest(
            CapExTestFixtures.getUser(CapExTestFixtures.REP).Id,
            amount
        );
        insert request;
        return request;
    }

    private static CapEx_Request__c reload(Id requestId) {
        return [SELECT Status__c, Approved_On__c, Ledger_Status__c FROM CapEx_Request__c WHERE Id = :requestId];
    }

    @IsTest
    static void approvalPublishesAnEventThatPostsToTheLedger() {
        ErpLedgerMock mock = ErpLedgerMock.install();
        CapEx_Request__c request = insertDraft(48000);

        Test.startTest();
        CapExTestFixtures.submitAndDecide(request.Id, 'Approve');
        CapEx_Request__c approved = reload(request.Id);
        Assert.areEqual(CapExService.STATUS_APPROVED, approved.Status__c);
        Assert.isNotNull(approved.Approved_On__c);
        Assert.areEqual(CapExService.LEDGER_PENDING, approved.Ledger_Status__c);
        Test.getEventBus().deliver();
        Assert.areEqual(LedgerPostingService.ENTRY_PENDING, CapExTestFixtures.ledgerEntry(request.Id).Status__c);
        Test.stopTest();

        Ledger_Entry__c entry = CapExTestFixtures.ledgerEntry(request.Id);
        Assert.areEqual(LedgerPostingService.ENTRY_POSTED, entry.Status__c, String.valueOf(entry));
        Assert.areEqual('ERP-' + String.valueOf(request.Id).right(6), entry.ERP_Reference__c);
        Assert.areEqual(48000, entry.Amount__c);
        Assert.areEqual(LedgerPostingService.LEDGER_POSTED, reload(request.Id).Ledger_Status__c);
        Assert.areEqual(1, mock.calls);
    }

    @IsTest
    static void rejectionPublishesNothing() {
        CapEx_Request__c request = insertDraft(9000);

        Test.startTest();
        CapExTestFixtures.submitAndDecide(request.Id, 'Reject');
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual('Rejected', reload(request.Id).Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Ledger_Entry__c]);
    }

    @IsTest
    static void replayedEventsNeverDoubleBook() {
        ErpLedgerMock.install();
        CapEx_Request__c request = insertDraft(1500);
        CapEx_Approved__e event = new CapEx_Approved__e(CapEx_Request_Id__c = request.Id, Amount__c = 1500);

        Test.startTest();
        EventBus.publish(new List<CapEx_Approved__e>{ event, event.clone() });
        Test.getEventBus().deliver();
        EventBus.publish(event.clone());
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Ledger_Entry__c WHERE CapEx_Request__c = :request.Id]);
    }

    @IsTest
    static void erpOutageRetriesThenFailsAndLogsAnError() {
        ErpLedgerMock mock = ErpLedgerMock.install();
        mock.statusCode = 503;
        LedgerPostingService.maxAttemptsOverride = 2;
        CapEx_Request__c request = insertDraft(2500);

        Test.startTest();
        CapExTestFixtures.submitAndDecide(request.Id, 'Approve');
        Test.getEventBus().deliver();
        Test.stopTest();
        Assert.areEqual(1, LedgerPostingJob.deferredInTests.size(), 'Attempt 1 failed: a retry was scheduled');
        CapExTestFixtures.runDeferredJobs();

        Ledger_Entry__c entry = CapExTestFixtures.ledgerEntry(request.Id);
        Assert.areEqual(LedgerPostingService.ENTRY_FAILED, entry.Status__c);
        Assert.areEqual(2, entry.Attempts__c);
        Assert.isTrue(entry.Last_Error__c.startsWith('ERP HTTP 503'), entry.Last_Error__c);
        Assert.areEqual(LedgerPostingService.LEDGER_FAILED, reload(request.Id).Ledger_Status__c);
        Assert.areEqual(2, mock.calls);
    }

    /**
     * @description Private OWD: the manager sees the team via the role hierarchy; peers and finance see no
     * drafts. The positive finance case (Approved_CapEx_to_Finance criteria-based rule) cannot be asserted
     * here: the platform writes criteria-based shares when the transaction commits, and test transactions
     * never commit. It is verified against a live org instead (docs/known-issues.md, KI-020).
     */
    @IsTest
    static void privateRequestsAreVisibleOnlyThroughTheHierarchy() {
        CapEx_Request__c draft = insertDraft(700);
        CapEx_Request__c submitted = insertDraft(800);
        BypassService.setTriggerBypass('CapEx_Request__c', true);
        update new CapEx_Request__c(Id = submitted.Id, Status__c = CapExService.STATUS_SUBMITTED);
        BypassService.setTriggerBypass('CapEx_Request__c', false);
        Set<Id> both = new Set<Id>{ draft.Id, submitted.Id };

        Assert.areEqual(
            both,
            visibleTo(CapExTestFixtures.MANAGER, both),
            'Manager sees the team via the role hierarchy'
        );
        Assert.isTrue(visibleTo(CapExTestFixtures.PEER, both).isEmpty(), 'Peers see nothing');
        Assert.isTrue(visibleTo(CapExTestFixtures.FINANCE, both).isEmpty(), 'Finance sees nothing before approval');
    }

    private static Set<Id> visibleTo(String lastName, Set<Id> requestIds) {
        Set<Id> visible = new Set<Id>();
        System.runAs(CapExTestFixtures.getUser(lastName)) {
            for (CapEx_Request__c request : CapExRequestsSelector.newInstance().selectById(requestIds)) {
                visible.add(request.Id);
            }
        }
        return visible;
    }

    @IsTest
    static void bulkApprovalOf200PostsInOneErpRequest() {
        ErpLedgerMock mock = ErpLedgerMock.install();
        Id repId = CapExTestFixtures.getUser(CapExTestFixtures.REP).Id;
        List<CapEx_Request__c> requests = new List<CapEx_Request__c>();
        for (Integer i = 0; i < 200; i++) {
            requests.add(CapExTestFixtures.newRequest(repId, 100 + i));
        }
        insert requests;

        Test.startTest();
        for (CapEx_Request__c request : requests) {
            request.Status__c = CapExService.STATUS_APPROVED;
        }
        update requests;
        Integer queriesUsed = Limits.getQueries();
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Ledger_Entry__c WHERE Status__c = :LedgerPostingService.ENTRY_POSTED]
        );
        Assert.areEqual(
            200,
            [SELECT COUNT() FROM CapEx_Request__c WHERE Ledger_Status__c = :LedgerPostingService.LEDGER_POSTED]
        );
        Assert.areEqual(1, mock.calls, 'One ERP request for the batch');
        Assert.isTrue(queriesUsed < 10, 'Producer must be bulkified, used ' + queriesUsed + ' queries');
    }

    /** @description A running job may queue only one child: remainder and retries travel together. */
    @IsTest
    static void oversizedBatchWithFailuresQueuesExactlyOneChildJob() {
        ErpLedgerMock mock = ErpLedgerMock.install();
        LedgerPostingService.postBatchSize = 2;
        Id repId = CapExTestFixtures.getUser(CapExTestFixtures.REP).Id;
        List<CapEx_Request__c> requests = new List<CapEx_Request__c>();
        for (Integer i = 0; i < 3; i++) {
            requests.add(CapExTestFixtures.newRequest(repId, 100 + i));
        }
        insert requests;
        List<Ledger_Entry__c> entries = new List<Ledger_Entry__c>();
        for (CapEx_Request__c request : requests) {
            entries.add(new Ledger_Entry__c(CapEx_Request__c = request.Id, Idempotency_Key__c = request.Id));
            mock.rejectedKeys.add(request.Id);
        }
        insert entries;
        Set<Id> entryIds = new Map<Id, Ledger_Entry__c>(entries).keySet();

        Test.startTest();
        System.enqueueJob(new LedgerPostingJob(entryIds));
        Test.stopTest();

        Assert.areEqual(1, mock.calls, 'One ERP request of postBatchSize entries');
        Assert.areEqual(1, LedgerPostingJob.deferredInTests.size(), 'At most one child job per running job');
        Assert.areEqual(entryIds, LedgerPostingJob.deferredInTests[0].entryIds, 'Remainder plus retries');
    }

    @IsTest
    static void bypassPublishesNothing() {
        CapEx_Request__c request = insertDraft(300);
        BypassService.setTriggerBypass('CapEx_Request__c', true);

        Test.startTest();
        update new CapEx_Request__c(Id = request.Id, Status__c = CapExService.STATUS_APPROVED);
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Ledger_Entry__c]);
        Assert.areEqual(CapExService.LEDGER_NOT_POSTED, reload(request.Id).Ledger_Status__c);
    }
}
