/**
 * @description Portal content: published-only reads, category filter, view mapping, and the guest user's
 * access (drafts are never readable by the site guest user).
 */
@IsTest
private class PortalContentServiceTest {
    private static Portal_Article__c article(String title, String status, String category, Integer daysAgo) {
        return new Portal_Article__c(
            Name = title,
            Summary__c = title + ' summary',
            Body__c = title + ' body',
            Category__c = category,
            Status__c = status,
            Published_On__c = status == 'Published' ? System.now().addDays(-daysAgo) : null
        );
    }

    @TestSetup
    static void setup() {
        insert new List<Portal_Article__c>{
            article('Spring spa offer', 'Published', 'Offers', 1),
            article('Harbour festival', 'Published', 'Events', 3),
            article('Packing tips', 'Published', 'Travel Tips', 2),
            article('Unapproved draft', 'Draft', 'Offers', 0),
            article('Pending review', 'In Review', 'Offers', 0)
        };
    }

    @IsTest
    static void returnsOnlyPublishedArticlesNewestFirst() {
        List<PortalContentService.ArticleView> views = PortalContentController.getPublishedArticles(null);

        Assert.areEqual(3, views.size(), 'Drafts and articles in review never reach the portal');
        Assert.areEqual('Spring spa offer', views[0].title);
        Assert.areEqual('Packing tips', views[1].title);
        Assert.areEqual('Spring spa offer summary', views[0].summary);
        Assert.areEqual('Offers', views[0].category);
        Assert.isNotNull(views[0].publishedOn);
    }

    @IsTest
    static void filtersByCategoryAndIgnoresUnknownCategories() {
        List<PortalContentService.ArticleView> events = PortalContentController.getPublishedArticles(' Events ');
        Assert.areEqual(1, events.size());
        Assert.areEqual('Harbour festival', events[0].title);

        Assert.isTrue(PortalContentController.getPublishedArticles('Secret').isEmpty(), 'Unknown category');
    }

    @IsTest
    static void selectorFailuresBecomeAFriendlyError() {
        PortalArticlesSelector.instance = (PortalArticlesSelector) new TestStub()
            .returns('selectPublished', new QueryException('boom'))
            .create(PortalArticlesSelector.class);
        try {
            PortalContentController.getPublishedArticles(null);
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException ex) {
            Assert.isTrue(Logger.getBufferSize() == 0, 'Logged and saved');
        }
    }

    /**
     * @description The site guest user never reads drafts. (The guest sharing rule for Published articles is
     * written at commit, so the positive guest case is verified in an org: docs/known-issues.md KI-020.)
     */
    @IsTest
    static void siteGuestUserCannotReadDrafts() {
        List<User> guests = [
            SELECT Id
            FROM User
            WHERE UserType = 'Guest' AND Profile.Name = 'Nexus Hospitality Profile' AND IsActive = TRUE
            LIMIT 1
        ];
        Assert.isFalse(guests.isEmpty(), 'The Nexus Hospitality site and its guest user exist');
        System.runAs(guests[0]) {
            for (PortalContentService.ArticleView view : PortalContentController.getPublishedArticles(null)) {
                Assert.areNotEqual('Unapproved draft', view.title);
                Assert.areNotEqual('Pending review', view.title);
            }
        }
    }
}
