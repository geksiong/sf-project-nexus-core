/**
 * @description Data-access SOQL for CapEx_Request__c, WITH USER_MODE: callers only see requests the
 * Private OWD, role hierarchy and sharing rules give them.
 */
public virtual with sharing class CapExRequestsSelector {
    @TestVisible
    private static CapExRequestsSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static CapExRequestsSelector newInstance() {
        if (instance == null) {
            instance = new CapExRequestsSelector();
        }
        return instance;
    }

    public virtual List<CapEx_Request__c> selectById(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new List<CapEx_Request__c>();
        }
        return [
            SELECT Id, Name, Ledger_Status__c
            FROM CapEx_Request__c
            WHERE Id IN :requestIds
            WITH USER_MODE
        ];
    }
}
