/**
 * @description Facts the deal registration rules evaluate. Partners cannot see other partners' registrations,
 * their channel manager's user record or existing customer accounts, yet the channel conflict rule, the
 * approval routing and the conversion must see all of them: WITH SYSTEM_MODE in a `without sharing` class
 * (AGENTS.md 2.1). Results are Ids or names only and never leave DealRegistrationService.
 */
public virtual without sharing class DealRegistrationFactsSelector {
    @TestVisible
    private static DealRegistrationFactsSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static DealRegistrationFactsSelector newInstance() {
        if (instance == null) {
            instance = new DealRegistrationFactsSelector();
        }
        return instance;
    }

    /** @description User Id to the partner account of the user's contact (partner users only). */
    public virtual Map<Id, Id> selectPartnerAccountIds(Set<Id> userIds) {
        Map<Id, Id> accountIds = new Map<Id, Id>();
        if (userIds == null || userIds.isEmpty()) {
            return accountIds;
        }
        for (User u : [
            SELECT Id, Contact.AccountId
            FROM User
            WHERE Id IN :userIds AND ContactId != NULL AND Contact.Account.IsPartner = TRUE
            WITH SYSTEM_MODE
        ]) {
            accountIds.put(u.Id, u.Contact.AccountId);
        }
        return accountIds;
    }

    /** @description Partner account Id to its owner (the channel manager), for active owners only. */
    public virtual Map<Id, Id> selectChannelManagerIds(Set<Id> partnerAccountIds) {
        Map<Id, Id> managerIds = new Map<Id, Id>();
        if (partnerAccountIds == null || partnerAccountIds.isEmpty()) {
            return managerIds;
        }
        for (Account acc : [
            SELECT Id, OwnerId
            FROM Account
            WHERE Id IN :partnerAccountIds AND Owner.IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            managerIds.put(acc.Id, acc.OwnerId);
        }
        return managerIds;
    }

    /**
     * @description Registrations that reserve their customer, as normalised company name to the registering
     * partner account Id, excluding the given registrations: Submitted, or Approved with a live reservation
     * (not past Expires_On__c and the opportunity not closed). Evaluated live, so a lapsed reservation releases
     * the customer immediately, before DealRegistrationExpiryJob updates its status.
     */
    public virtual Map<String, Id> selectOpenRegistrationPartners(Set<String> companyKeys, Set<Id> excludeIds) {
        Map<String, Id> partners = new Map<String, Id>();
        if (companyKeys == null || companyKeys.isEmpty()) {
            return partners;
        }
        Set<Id> excluded = excludeIds == null ? new Set<Id>() : excludeIds;
        for (Deal_Registration__c reg : [
            SELECT Customer_Company__c, Partner_Account__c
            FROM Deal_Registration__c
            WHERE
                Customer_Company__c IN :companyKeys
                AND Id NOT IN :excluded
                AND (Status__c = :DealRegistrationService.STATUS_SUBMITTED
                OR (Status__c = :DealRegistrationService.STATUS_APPROVED
                AND (Expires_On__c = NULL
                OR Expires_On__c >= TODAY)
                AND (Opportunity__c = NULL
                OR Opportunity__r.IsClosed = FALSE)))
            WITH SYSTEM_MODE
        ]) {
            partners.put(DealRegistrationService.companyKey(reg.Customer_Company__c), reg.Partner_Account__c);
        }
        return partners;
    }

    /**
     * @description Approved registrations whose reservation has lapsed (past Expires_On__c, or opportunity closed),
     * for DealRegistrationExpiryJob (system automation: minimal records, never returned to a user).
     */
    public virtual List<Deal_Registration__c> selectLapsedReservations(Integer maxRecords) {
        return [
            SELECT Id, Expires_On__c, Opportunity__r.IsClosed
            FROM Deal_Registration__c
            WHERE
                Status__c = :DealRegistrationService.STATUS_APPROVED
                AND (Expires_On__c < TODAY
                OR Opportunity__r.IsClosed = TRUE)
            WITH SYSTEM_MODE
            LIMIT :maxRecords
        ];
    }

    /** @description Existing customer (non-partner) accounts by normalised name, to reuse on conversion. */
    public virtual Map<String, Id> selectAccountIdsByName(Set<String> companyKeys) {
        Map<String, Id> accountIds = new Map<String, Id>();
        if (companyKeys == null || companyKeys.isEmpty()) {
            return accountIds;
        }
        for (Account acc : [
            SELECT Id, Name
            FROM Account
            WHERE Name IN :companyKeys AND IsPartner = FALSE
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ]) {
            String key = DealRegistrationService.companyKey(acc.Name);
            if (!accountIds.containsKey(key)) {
                accountIds.put(key, acc.Id);
            }
        }
        return accountIds;
    }
}
