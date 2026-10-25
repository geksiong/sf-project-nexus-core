/**
 * @description Sole SOQL authority for Account within the sales engine. All queries run WITH USER_MODE.
 */
public with sharing class AccountsSelector {
    public static Map<Id, Account> selectByIdWithCreditStatus(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>([
            SELECT Id, Name, Credit_Hold__c
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ]);
    }
}
