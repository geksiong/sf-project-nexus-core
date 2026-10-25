/**
 * @description Facts the sales engine's business rules evaluate (stage gates, approval routing).
 *
 * Rules are invariants: they must give the same answer whoever saves the record (sales reps,
 * integration users, partners, agents). This selector therefore runs WITH SYSTEM_MODE in a
 * `without sharing` class, unlike data-access selectors, which run WITH USER_MODE.
 *
 * Contract (enforced by the Nexus PMD rules and the metadata audit):
 *  - Methods answer a narrow question and return Ids, flags or hierarchy-only records.
 *  - Results feed rule evaluation inside services only; they are never returned to a caller,
 *    and *FactsSelector classes must not be referenced from @AuraEnabled / invocable / REST classes.
 */
public virtual without sharing class SalesEngineFactsSelector {
    @TestVisible
    private static SalesEngineFactsSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static SalesEngineFactsSelector newInstance() {
        if (instance == null) {
            instance = new SalesEngineFactsSelector();
        }
        return instance;
    }

    /** @description Ids of the given accounts that have an active credit hold. */
    public virtual Set<Id> selectAccountIdsOnCreditHold(Set<Id> accountIds) {
        Set<Id> onHold = new Set<Id>();
        if (accountIds == null || accountIds.isEmpty()) {
            return onHold;
        }
        for (Account acc : [
            SELECT Id
            FROM Account
            WHERE Id IN :accountIds AND Credit_Hold__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            onHold.add(acc.Id);
        }
        return onHold;
    }

    /** @description Ids of the given opportunities that have a primary contact role. */
    public virtual Set<Id> selectOpportunityIdsWithPrimaryContact(Set<Id> oppIds) {
        Set<Id> withPrimary = new Set<Id>();
        if (oppIds == null || oppIds.isEmpty()) {
            return withPrimary;
        }
        for (OpportunityContactRole ocr : [
            SELECT OpportunityId
            FROM OpportunityContactRole
            WHERE OpportunityId IN :oppIds AND IsPrimary = TRUE
            WITH SYSTEM_MODE
        ]) {
            withPrimary.add(ocr.OpportunityId);
        }
        return withPrimary;
    }

    /** @description Users with only their two-level manager chain, for approver routing. */
    public virtual Map<Id, User> selectManagerChains(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>(
            [
                SELECT Id, ManagerId, Manager.IsActive, Manager.ManagerId, Manager.Manager.IsActive
                FROM User
                WHERE Id IN :userIds
                WITH SYSTEM_MODE
            ]
        );
    }
}
