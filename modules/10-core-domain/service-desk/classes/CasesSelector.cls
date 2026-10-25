/**
 * @description Data-access SOQL for Case. All queries run WITH USER_MODE: callers only see the cases,
 * and fields, the running user can access.
 */
public virtual with sharing class CasesSelector {
    @TestVisible
    private static CasesSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static CasesSelector newInstance() {
        if (instance == null) {
            instance = new CasesSelector();
        }
        return instance;
    }

    public virtual List<Case> selectById(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return new List<Case>();
        }
        return [
            SELECT Id, CaseNumber, Subject, Status, IsClosed, Priority, OwnerId, AccountId, Escalation_Reason__c
            FROM Case
            WHERE Id IN :caseIds
            WITH USER_MODE
        ];
    }
}
