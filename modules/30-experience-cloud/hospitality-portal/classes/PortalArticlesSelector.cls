/**
 * @description Data-access SOQL for Portal_Article__c, WITH USER_MODE. On the Nexus Hospitality site the
 * running user is the site guest user, so the guest sharing rule (Published only) decides what is visible;
 * the Status filter is defence in depth, not the access control.
 */
public virtual with sharing class PortalArticlesSelector {
    @TestVisible
    private static PortalArticlesSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static PortalArticlesSelector newInstance() {
        if (instance == null) {
            instance = new PortalArticlesSelector();
        }
        return instance;
    }

    /** @description Published articles, newest first; `category` null for all categories. */
    public virtual List<Portal_Article__c> selectPublished(String category, Integer maxRecords) {
        String status = PortalContentService.STATUS_PUBLISHED;
        if (String.isBlank(category)) {
            return [
                SELECT Id, Name, Summary__c, Body__c, Category__c, Published_On__c
                FROM Portal_Article__c
                WHERE Status__c = :status
                WITH USER_MODE
                ORDER BY Published_On__c DESC NULLS LAST
                LIMIT :maxRecords
            ];
        }
        return [
            SELECT Id, Name, Summary__c, Body__c, Category__c, Published_On__c
            FROM Portal_Article__c
            WHERE Status__c = :status AND Category__c = :category
            WITH USER_MODE
            ORDER BY Published_On__c DESC NULLS LAST
            LIMIT :maxRecords
        ];
    }
}
