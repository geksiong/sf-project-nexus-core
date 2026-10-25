# ADR 0002: Decouple Ledger Creation via Platform Events

* **Status:** Accepted
* **Deciders:** Enterprise Architecture Lead & Platform Engineers
* **Date:** 2026-10-22 (implemented in Phase 4, 2026-10-25)

## Context and Problem Statement
An approved CapEx request must become a ledger posting in the ERP. Doing that inside the approval transaction
couples the approver's click to an external system: Apex cannot make a callout after DML in the same transaction,
an ERP outage would block or roll back the approval, and every future consumer of "CapEx approved" (analytics,
notifications, Agentforce) would have to be wired into the same trigger.

## Decision Drivers
* An approval must commit regardless of ERP availability.
* A ledger posting must happen exactly once per approved request, even when events are redelivered.
* Failures must be visible and recoverable without data fixes.
* New consumers must be addable without changing the producer.

## Considered Options
1. **Synchronous callout** from the approval (`@future(callout=true)` from the trigger).
2. **Queueable from the trigger** that creates the ledger entry and posts it.
3. **Platform event** `CapEx_Approved__e` (producer) + event-triggered consumer + queueable posting job.

## Decision
Option 3. `CapExService` publishes `CapEx_Approved__e` (`PublishAfterCommit`) when the approval process sets
`Status__c = Approved`. The `CapExApprovedTrigger` consumer (`LedgerPostingService.recordApprovals`) records one
`Ledger_Entry__c` per request and enqueues `LedgerPostingJob`, which posts to the ERP through the `Mock_ERP_Ledger`
named credential.

Rules that make it safe:
* **After commit only:** `PublishAfterCommit` means a rolled-back approval never produces an event.
* **Idempotent consumer:** the entry's `Idempotency_Key__c` (external Id, unique) is the request Id. Duplicate or
  replayed events are skipped, and the key is sent to the ERP so a repeated post is not double-booked.
* **System context:** the consumer runs as the Automated Process user and the job as the enqueuing user; neither
  acts for a person, so their reads use `CapExFactsSelector` and their writes run in system mode.
* **Retries:** row-lock contention in the consumer throws `EventBus.RetryableException` (platform redelivery);
  ERP failures retry in new jobs with growing delays (1, 5, 15, 30 min) up to
  `ERP_Ledger_Setting__mdt.Max_Attempts__c`, then the entry is `Failed`, the request's `Ledger_Status__c` is
  `Failed` and an ERROR is logged to the Admin Cockpit feed. `RetryLedgerPostingAction` re-queues it.
* **Recovery of lost events:** an approval whose event was never published or consumed stays `Pending` with no
  ledger entry. After 10 minutes `RetryLedgerPostingAction` rebuilds the entry from the approved request through
  the same idempotent path as the consumer.

## Consequences
* **Positive:** approvals never wait on, or fail because of, the ERP; the ledger is exactly-once per request;
  failures are observable and recoverable; other subscribers can be added to `CapEx_Approved__e` independently.
* **Negative:** posting is eventually consistent (seconds to minutes); the consumer's running user is the
  Automated Process user, so it needs system-mode access by design; tests must deliver events explicitly
  (`Test.getEventBus().deliver()`) and cannot chain queueables (`LedgerPostingJob.deferredInTests`).
* **Demo orgs:** the mock ERP endpoint does not exist, so `ERP_Ledger_Setting.Default.Simulate__c` returns
  synthetic `SIM-` references. Turn it off and point the named credential at a real endpoint to integrate.
