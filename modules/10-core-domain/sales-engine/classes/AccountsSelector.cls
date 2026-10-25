/**
 * @description Sole SOQL authority for Account within the sales engine. All queries run WITH USER_MODE.
 */
public virtual with sharing class AccountsSelector {
    @TestVisible
    private static AccountsSelector instance;

    /** @description Returns the selector; tests replace it with a Test.createStub() mock via `instance`. */
    public static AccountsSelector newInstance() {
        if (instance == null) {
            instance = new AccountsSelector();
        }
        return instance;
    }

    public virtual Map<Id, Account> selectByIdWithCreditStatus(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>(
            [
                SELECT Id, Name, Credit_Hold__c
                FROM Account
                WHERE Id IN :accountIds
                WITH USER_MODE
            ]
        );
    }
}
