/**
 * @description Sole SOQL authority for Opportunity. All queries run WITH USER_MODE.
 */
public virtual with sharing class OpportunitiesSelector {
    @TestVisible
    private static OpportunitiesSelector instance;

    /** @description Returns the selector; tests replace it with a Test.createStub() mock via `instance`. */
    public static OpportunitiesSelector newInstance() {
        if (instance == null) {
            instance = new OpportunitiesSelector();
        }
        return instance;
    }

    public virtual List<Opportunity> selectByIdWithDetails(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) {
            return new List<Opportunity>();
        }
        return [
            SELECT
                Id,
                Name,
                AccountId,
                OwnerId,
                StageName,
                Amount,
                CloseDate,
                IsClosed,
                IsWon,
                Discount_Percentage__c,
                Approval_Tier__c,
                Discount_Approval_Status__c,
                Loss_Reason__c,
                Account.Name,
                Account.Credit_Hold__c,
                (SELECT Id, ContactId, Role, IsPrimary FROM OpportunityContactRoles),
                (SELECT Id, Quantity, UnitPrice, TotalPrice, PricebookEntry.Product2.Name FROM OpportunityLineItems)
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH USER_MODE
        ];
    }
}
