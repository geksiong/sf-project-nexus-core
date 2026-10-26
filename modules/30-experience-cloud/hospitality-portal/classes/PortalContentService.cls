/**
 * @description Published hospitality content for the Nexus Hospitality LWR site (Demo App 5). Content goes
 * live through the Portal Content Approval process; guests can only ever read Published articles (guest
 * sharing rule + Status filter) and only the fields the portal shows.
 */
public with sharing class PortalContentService {
    public static final String STATUS_PUBLISHED = 'Published';
    @TestVisible
    private static final Integer MAX_ARTICLES = 20;

    /** @description What the portal renders: no Ids of internal users, no workflow fields. */
    public class ArticleView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String summary;
        @AuraEnabled
        public String body;
        @AuraEnabled
        public String category;
        @AuraEnabled
        public Datetime publishedOn;
    }

    /** @description Up to MAX_ARTICLES published articles; an unknown category returns nothing. */
    public static List<ArticleView> publishedArticles(String category) {
        String filter = String.isBlank(category) ? null : category.trim();
        if (filter != null && !isCategory(filter)) {
            return new List<ArticleView>();
        }
        List<ArticleView> views = new List<ArticleView>();
        for (Portal_Article__c article : PortalArticlesSelector.newInstance().selectPublished(filter, MAX_ARTICLES)) {
            ArticleView view = new ArticleView();
            view.id = article.Id;
            view.title = article.Name;
            view.summary = article.Summary__c;
            view.body = article.Body__c;
            view.category = article.Category__c;
            view.publishedOn = article.Published_On__c;
            views.add(view);
        }
        return views;
    }

    private static Boolean isCategory(String value) {
        for (Schema.PicklistEntry entry : Portal_Article__c.Category__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == value) {
                return true;
            }
        }
        return false;
    }
}
