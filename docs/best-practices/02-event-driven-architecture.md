# Nexus Core Engineering Standard: Event-Driven Architecture

- **Standard Code:** `BP-EDA-002`
- **Module Target:** `modules/10-core-domain/event-bus/` (event definitions), consumers in the owning feature
  (`capex-operations/`)
- **Related ADR:** `docs/adr/0002-decoupling-via-platform-events.md`
- **Reference implementation:** `CapEx_Approved__e` → `CapExApprovedTrigger` → `LedgerPostingService` →
  `LedgerPostingJob` → `ErpLedgerClient`

---

## 1. When to publish an event

Publish a platform event when a business fact must reach something that **must not share the transaction**: an
external system (callouts cannot follow DML), a slow or failure-prone step, or consumers the producer should not
know about. Keep same-transaction rules (validation, derived fields) in the trigger and service.

## 2. Producer rules

- Publish from the service, in the **after** trigger context, for the state **transition** only
  (`Status__c` becomes `Approved`), never for every save.
- Use `publishBehavior = PublishAfterCommit` (`CapEx_Approved__e`), so rolled-back work never produces events.
- Carry the facts consumers need (Id, amount, department, time). Do not make consumers query back for fields that
  may have changed since.
- Check `EventBus.publish` results and log failures (`Logger.error`).

## 3. Consumer rules

- Event triggers are one line and extend `TriggerHandler` (`afterInsert` only), like any other trigger.
- **Idempotency is mandatory.** Events can be redelivered. Key the created record on a unique external Id derived
  from the source record (`Ledger_Entry__c.Idempotency_Key__c` = request Id) and skip keys that exist.
- The consumer runs as the **Automated Process** user. It acts for no person, so reads go through a `*FactsSelector`
  (`WITH SYSTEM_MODE`) and writes use `AccessLevel.SYSTEM_MODE` (AGENTS.md 2.1).
- Transient errors (`UNABLE_TO_LOCK_ROW`): throw `EventBus.RetryableException` while
  `EventBus.TriggerContext.currentContext().retries` is below the cap; the platform redelivers the batch.
- Permanent errors: log them (`PartialDml.save`) and carry on; one bad event must not block the batch.
- No callouts in the event trigger: enqueue a `Queueable` with `Database.AllowsCallouts`.

## 4. Async integration jobs

- One job posts one batch (≤ 200 records, one callout); remainders go to a new job.
- Callouts happen **before** any DML in the job's transaction.
- Retry by enqueueing a new job with a delay (`System.enqueueJob(job, minutes)`), growing per attempt, up to a
  configured maximum (`ERP_Ledger_Setting__mdt.Max_Attempts__c`). After the last attempt mark the record `Failed`,
  surface it on the parent (`Ledger_Status__c`) and log an ERROR (Admin Cockpit feed).
- Offer a recovery action with the result envelope (`RetryLedgerPostingAction`) that authorises in user mode
  before re-queueing in system mode.
- Callouts go through a named credential (`callout:Mock_ERP_Ledger/...`), never a hard-coded URL.

## 5. Testing

| Concern | How |
| --- | --- |
| Producer | Unit-test event planning in memory (`CapExService.planApprovalEvents`). |
| Consumer | `EventBus.publish(...)` then `Test.getEventBus().deliver()`; publish the same event twice to prove idempotency. |
| Job | Runs at `Test.stopTest()`. Jobs it chains are captured in `LedgerPostingJob.deferredInTests` (tests cannot chain queueables) and run explicitly. |
| Callouts | `HttpCalloutMock` (`ErpLedgerMock`): success, per-record rejection, HTTP error, malformed body. |
| Sharing | Criteria-based shares are written at commit, so they cannot be asserted in Apex tests; verify them in an org. |
