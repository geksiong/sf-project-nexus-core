/**
 * @description Guest-accessible controller for the hospitalityArticles LWC on the Nexus Hospitality site.
 * Runs as the site guest user (with sharing, user-mode queries): no `without sharing` shortcut.
 */
public with sharing class PortalContentController {
    @AuraEnabled(cacheable=true)
    public static List<PortalContentService.ArticleView> getPublishedArticles(String category) {
        try {
            return PortalContentService.publishedArticles(category);
        } catch (Exception ex) {
            Logger.error('Portal content could not be loaded: ' + ex.getMessage(), ex);
            Logger.saveLog();
            throw new AuraHandledException('Content is temporarily unavailable.');
        }
    }
}
