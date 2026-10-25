/**
 * @description Posts ledger entries to the ERP asynchronously (callouts are not allowed in a platform event
 * trigger). Retries are new jobs with a growing delay, scheduled by LedgerPostingService.
 */
public with sharing class LedgerPostingJob implements Queueable, Database.AllowsCallouts {
    /** @description Jobs a running job tried to chain inside a test (tests cannot chain queueables). */
    @TestVisible
    private static List<LedgerPostingJob> deferredInTests = new List<LedgerPostingJob>();

    @TestVisible
    private final Set<Id> entryIds;

    public LedgerPostingJob(Set<Id> entryIds) {
        this.entryIds = entryIds;
    }

    public void execute(QueueableContext context) {
        LedgerPostingService.postEntries(entryIds);
    }

    public static void enqueue(Set<Id> entryIds, Integer delayMinutes) {
        LedgerPostingJob job = new LedgerPostingJob(entryIds);
        if (Test.isRunningTest() && System.isQueueable()) {
            deferredInTests.add(job);
        } else if (delayMinutes > 0) {
            System.enqueueJob(job, delayMinutes);
        } else {
            System.enqueueJob(job);
        }
    }
}
