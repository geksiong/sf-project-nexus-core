/**
 * @description Reads for the CapEx ledger integration's system automation: the CapEx_Approved__e consumer
 * (Automated Process user) and LedgerPostingJob act on no person's behalf, so their reads run WITH
 * SYSTEM_MODE in a `without sharing` class (AGENTS.md 2.1). Methods return Ids, or the minimal records a
 * job posts; results never reach a user.
 */
public virtual without sharing class CapExFactsSelector {
    @TestVisible
    private static CapExFactsSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static CapExFactsSelector newInstance() {
        if (instance == null) {
            instance = new CapExFactsSelector();
        }
        return instance;
    }

    /** @description Existing ledger entries by idempotency key (the CapEx request Id). */
    public virtual Map<String, Id> selectLedgerEntryIdsByKey(Set<String> keys) {
        Map<String, Id> entryIds = new Map<String, Id>();
        if (keys == null || keys.isEmpty()) {
            return entryIds;
        }
        for (Ledger_Entry__c entry : [
            SELECT Id, Idempotency_Key__c
            FROM Ledger_Entry__c
            WHERE Idempotency_Key__c IN :keys
            WITH SYSTEM_MODE
        ]) {
            entryIds.put(entry.Idempotency_Key__c, entry.Id);
        }
        return entryIds;
    }

    /** @description Posting payload for the given entries that are still Pending. */
    public virtual List<Ledger_Entry__c> selectPendingEntries(Set<Id> entryIds) {
        if (entryIds == null || entryIds.isEmpty()) {
            return new List<Ledger_Entry__c>();
        }
        return [
            SELECT Id, CapEx_Request__c, Amount__c, Department__c, Idempotency_Key__c, Attempts__c
            FROM Ledger_Entry__c
            WHERE Id IN :entryIds AND Status__c = :LedgerPostingService.ENTRY_PENDING
            WITH SYSTEM_MODE
        ];
    }

    /** @description Approval facts (amount, department, time) of approved requests, to recover a lost event. */
    public virtual List<CapEx_Request__c> selectApprovedRequests(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new List<CapEx_Request__c>();
        }
        return [
            SELECT Id, Total_Amount__c, Department__c, Approved_On__c
            FROM CapEx_Request__c
            WHERE Id IN :requestIds AND Status__c = :CapExService.STATUS_APPROVED
            WITH SYSTEM_MODE
        ];
    }

    /** @description Failed ledger entries of the given CapEx requests. */
    public virtual Set<Id> selectFailedEntryIds(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Set<Id>();
        }
        return new Map<Id, Ledger_Entry__c>(
                [
                    SELECT Id
                    FROM Ledger_Entry__c
                    WHERE CapEx_Request__c IN :requestIds AND Status__c = :LedgerPostingService.ENTRY_FAILED
                    WITH SYSTEM_MODE
                ]
            )
            .keySet();
    }
}
