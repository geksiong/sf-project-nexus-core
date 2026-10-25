/**
 * @description Consumer side of the CapEx ledger integration (ADR 0002).
 *
 *  recordApprovals   CapEx_Approved__e trigger: one Pending Ledger_Entry__c per request, keyed by the request
 *                    Id (Idempotency_Key__c), so replayed or duplicate events never double-book. Row-lock
 *                    contention throws EventBus.RetryableException so the platform redelivers the batch.
 *  postEntries       LedgerPostingJob: posts Pending entries to the ERP; failures retry with a growing
 *                    delay up to ERP_Ledger_Setting__mdt.Max_Attempts__c, then become Failed and are logged
 *                    as errors (Admin Cockpit feed).
 *  retryFailedPostings  RetryLedgerPostingAction: an authorised user re-queues a failed posting.
 *
 * Writes from the consumer and the job are system automation (Automated Process / enqueuing user), so
 * they run in system mode; the retry action authorises with a user-mode update first.
 */
public with sharing class LedgerPostingService {
    public static final String ENTRY_PENDING = 'Pending';
    public static final String ENTRY_POSTED = 'Posted';
    public static final String ENTRY_FAILED = 'Failed';
    public static final String LEDGER_PENDING = 'Pending';
    public static final String LEDGER_POSTED = 'Posted';
    public static final String LEDGER_FAILED = 'Failed';

    public static final String ERROR_INVALID_INPUT = 'INVALID_INPUT';
    public static final String ERROR_NOT_FOUND = 'NOT_FOUND';
    public static final String ERROR_INVALID_STATE = 'INVALID_STATE';
    public static final String ERROR_DML = 'DML_ERROR';

    /** @description ERP request size; also keeps one job well inside callout and heap limits. */
    @TestVisible
    private static final Integer POST_BATCH_SIZE = 200;
    private static final Integer MAX_EVENT_RETRIES = 4;
    private static final List<Integer> RETRY_DELAYS_MINUTES = new List<Integer>{ 1, 5, 15, 30 };

    @TestVisible
    private static Integer maxAttemptsOverride;

    // ---------------------------------------------------------------------------------------------
    // Platform event consumer
    // ---------------------------------------------------------------------------------------------

    public static void recordApprovals(List<CapEx_Approved__e> events) {
        List<Ledger_Entry__c> entries = planLedgerEntries(events);
        if (entries.isEmpty()) {
            if (Logger.getBufferSize() > 0) {
                Logger.saveLog();
            }
            return;
        }
        List<Database.SaveResult> results = Database.insert(entries, false, AccessLevel.SYSTEM_MODE);
        Set<Id> created = new Set<Id>();
        Boolean lockContention = false;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                created.add(result.getId());
            } else {
                for (Database.Error err : result.getErrors()) {
                    lockContention |= err.getStatusCode() == StatusCode.UNABLE_TO_LOCK_ROW;
                }
            }
        }
        if (lockContention && EventBus.TriggerContext.currentContext().retries < MAX_EVENT_RETRIES) {
            // Rolls back this batch; the platform redelivers it with retries + 1.
            throw new EventBus.RetryableException('Ledger entry insert hit row lock contention; retrying the batch.');
        }
        PartialDml.save(results, 'Ledger entry creation');
        if (!created.isEmpty()) {
            LedgerPostingJob.enqueue(created, 0);
        }
    }

    /** @description New Pending entries for the events, skipping requests that already have one (no DML). */
    @TestVisible
    private static List<Ledger_Entry__c> planLedgerEntries(List<CapEx_Approved__e> events) {
        Map<String, CapEx_Approved__e> eventsByKey = new Map<String, CapEx_Approved__e>();
        for (CapEx_Approved__e event : events) {
            if (event.CapEx_Request_Id__c instanceof Id && !eventsByKey.containsKey(event.CapEx_Request_Id__c)) {
                eventsByKey.put(event.CapEx_Request_Id__c, event);
            } else if (!(event.CapEx_Request_Id__c instanceof Id)) {
                Logger.error(
                    'CapEx_Approved__e ignored: invalid CapEx_Request_Id__c "' + event.CapEx_Request_Id__c + '"'
                );
            }
        }
        Map<String, Id> existing = CapExFactsSelector.newInstance().selectLedgerEntryIdsByKey(eventsByKey.keySet());

        List<Ledger_Entry__c> entries = new List<Ledger_Entry__c>();
        for (String key : eventsByKey.keySet()) {
            if (existing.containsKey(key)) {
                continue;
            }
            CapEx_Approved__e event = eventsByKey.get(key);
            entries.add(
                new Ledger_Entry__c(
                    CapEx_Request__c = key,
                    Idempotency_Key__c = key,
                    Amount__c = event.Amount__c,
                    Department__c = event.Department__c,
                    Status__c = ENTRY_PENDING,
                    Attempts__c = 0
                )
            );
        }
        return entries;
    }

    // ---------------------------------------------------------------------------------------------
    // ERP posting (LedgerPostingJob)
    // ---------------------------------------------------------------------------------------------

    public static void postEntries(Set<Id> entryIds) {
        List<Ledger_Entry__c> pending = CapExFactsSelector.newInstance().selectPendingEntries(entryIds);
        if (pending.isEmpty()) {
            return;
        }
        List<Ledger_Entry__c> batch = new List<Ledger_Entry__c>();
        Set<Id> remainder = new Set<Id>();
        for (Ledger_Entry__c entry : pending) {
            if (batch.size() < POST_BATCH_SIZE) {
                batch.add(entry);
            } else {
                remainder.add(entry.Id);
            }
        }

        // Callout before any DML in this transaction.
        Map<String, ErpLedgerClient.PostResult> results = ErpLedgerClient.newInstance().post(batch);
        PostingOutcome outcome = applyPostingResults(batch, results, maxAttempts());

        for (Ledger_Entry__c failed : outcome.finalFailures) {
            Logger.error(
                'ERP ledger posting failed after ' + failed.Attempts__c + ' attempt(s): ' + failed.Last_Error__c,
                failed.Id
            );
        }
        PartialDml.save(Database.update(outcome.entries, false, AccessLevel.SYSTEM_MODE), 'Ledger entry posting');
        if (!outcome.requests.isEmpty()) {
            PartialDml.save(
                Database.update(outcome.requests, false, AccessLevel.SYSTEM_MODE),
                'CapEx ledger status update'
            );
        }
        if (!outcome.retryIds.isEmpty()) {
            LedgerPostingJob.enqueue(outcome.retryIds, retryDelay(outcome.highestAttempt));
        }
        if (!remainder.isEmpty()) {
            LedgerPostingJob.enqueue(remainder, 0);
        }
    }

    /** @description Entry and request updates for one ERP response (no DML). */
    @TestVisible
    private static PostingOutcome applyPostingResults(
        List<Ledger_Entry__c> entries,
        Map<String, ErpLedgerClient.PostResult> results,
        Integer maxAttempts
    ) {
        PostingOutcome outcome = new PostingOutcome();
        Datetime now = System.now();
        for (Ledger_Entry__c entry : entries) {
            ErpLedgerClient.PostResult result = results.get(entry.Idempotency_Key__c);
            Integer attempts = (entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue()) + 1;
            outcome.highestAttempt = Math.max(outcome.highestAttempt, attempts);
            Ledger_Entry__c updated = new Ledger_Entry__c(Id = entry.Id, Attempts__c = attempts);
            if (result != null && result.success) {
                updated.Status__c = ENTRY_POSTED;
                updated.ERP_Reference__c = result.reference;
                updated.Posted_On__c = now;
                updated.Last_Error__c = null;
                outcome.requests.add(
                    new CapEx_Request__c(Id = entry.CapEx_Request__c, Ledger_Status__c = LEDGER_POSTED)
                );
            } else {
                updated.Last_Error__c = (result == null ? 'No ERP result.' : result.error).abbreviate(255);
                if (attempts < maxAttempts) {
                    outcome.retryIds.add(entry.Id);
                } else {
                    updated.Status__c = ENTRY_FAILED;
                    outcome.finalFailures.add(updated);
                    outcome.requests.add(
                        new CapEx_Request__c(Id = entry.CapEx_Request__c, Ledger_Status__c = LEDGER_FAILED)
                    );
                }
            }
            outcome.entries.add(updated);
        }
        return outcome;
    }

    @TestVisible
    private class PostingOutcome {
        public List<Ledger_Entry__c> entries = new List<Ledger_Entry__c>();
        public List<CapEx_Request__c> requests = new List<CapEx_Request__c>();
        public List<Ledger_Entry__c> finalFailures = new List<Ledger_Entry__c>();
        public Set<Id> retryIds = new Set<Id>();
        public Integer highestAttempt = 0;
    }

    @TestVisible
    private static Integer maxAttempts() {
        if (maxAttemptsOverride != null) {
            return maxAttemptsOverride;
        }
        ERP_Ledger_Setting__mdt setting = ERP_Ledger_Setting__mdt.getInstance('Default');
        return setting?.Max_Attempts__c == null ? 3 : Math.max(1, setting.Max_Attempts__c.intValue());
    }

    @TestVisible
    private static Integer retryDelay(Integer attemptsSoFar) {
        return RETRY_DELAYS_MINUTES[Math.min(attemptsSoFar, RETRY_DELAYS_MINUTES.size()) - 1];
    }

    // ---------------------------------------------------------------------------------------------
    // Manual retry (RetryLedgerPostingAction)
    // ---------------------------------------------------------------------------------------------

    /**
     * @description Re-queues failed postings. The request update runs in user mode, so only users who may
     * edit Ledger_Status__c (PS_CapEx_Admin) can retry; the entries are then reset in system mode.
     */
    public static List<RetryLedgerPostingAction.Result> retryFailedPostings(
        List<RetryLedgerPostingAction.Request> requests
    ) {
        List<RetryLedgerPostingAction.Result> results = new List<RetryLedgerPostingAction.Result>();
        Map<Id, Integer> indexByRequestId = new Map<Id, Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            results.add(new RetryLedgerPostingAction.Result());
            Id requestId = requests[i].capexRequestId;
            String inputError = requestId == null
                ? 'CapEx Request Id is required.'
                : requestId.getSObjectType() != CapEx_Request__c.SObjectType
                      ? 'CapEx Request Id does not reference a CapEx request.'
                      : indexByRequestId.containsKey(requestId) ? 'Duplicate request in one batch.' : null;
            if (inputError != null) {
                fail(results[i], ERROR_INVALID_INPUT, inputError, requestId, true);
            } else {
                indexByRequestId.put(requestId, i);
            }
        }

        Map<Id, CapEx_Request__c> visible = new Map<Id, CapEx_Request__c>(
            CapExRequestsSelector.newInstance().selectById(indexByRequestId.keySet())
        );
        List<CapEx_Request__c> updates = new List<CapEx_Request__c>();
        for (Id requestId : indexByRequestId.keySet()) {
            Integer i = indexByRequestId.get(requestId);
            CapEx_Request__c request = visible.get(requestId);
            if (request == null) {
                fail(results[i], ERROR_NOT_FOUND, 'CapEx request not found or not accessible.', requestId, true);
            } else if (request.Ledger_Status__c != LEDGER_FAILED) {
                fail(
                    results[i],
                    ERROR_INVALID_STATE,
                    'Only failed postings can be retried (' + request.Name + ' is ' + request.Ledger_Status__c + ').',
                    requestId,
                    true
                );
            } else {
                updates.add(new CapEx_Request__c(Id = requestId, Ledger_Status__c = LEDGER_PENDING));
            }
        }

        List<Database.SaveResult> saveResults = Database.update(updates, false, AccessLevel.USER_MODE);
        Set<Id> retried = new Set<Id>();
        for (Integer j = 0; j < saveResults.size(); j++) {
            Id requestId = updates[j].Id;
            Integer i = indexByRequestId.get(requestId);
            if (saveResults[j].isSuccess()) {
                retried.add(requestId);
                results[i].isSuccess = true;
                results[i].payload = new RetryLedgerPostingAction.OutputPayload();
                results[i].payload.capexRequestId = requestId;
                results[i].payload.ledgerStatus = LEDGER_PENDING;
            } else {
                fail(results[i], ERROR_DML, saveResults[j].getErrors()[0].getMessage(), requestId, true);
            }
        }

        Set<Id> entryIds = CapExFactsSelector.newInstance().selectFailedEntryIds(retried);
        if (!entryIds.isEmpty()) {
            List<Ledger_Entry__c> resets = new List<Ledger_Entry__c>();
            for (Id entryId : entryIds) {
                resets.add(new Ledger_Entry__c(Id = entryId, Status__c = ENTRY_PENDING, Attempts__c = 0));
            }
            PartialDml.save(Database.update(resets, false, AccessLevel.SYSTEM_MODE), 'Ledger entry retry');
            LedgerPostingJob.enqueue(entryIds, 0);
        } else if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
        return results;
    }

    private static void fail(
        RetryLedgerPostingAction.Result result,
        String code,
        String message,
        Id recordId,
        Boolean isExpected
    ) {
        result.isSuccess = false;
        result.errorCode = code;
        result.errorMessage = message;
        String logMessage = 'RetryLedgerPostingAction ' + code + ': ' + message;
        if (isExpected) {
            Logger.warn(logMessage, recordId);
        } else {
            Logger.error(logMessage, recordId);
        }
    }
}
