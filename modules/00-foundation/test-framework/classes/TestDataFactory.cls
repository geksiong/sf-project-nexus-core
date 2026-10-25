/**
 * @description Shared test data builders for standard objects. Module-specific fields
 * (e.g. Opportunity.Discount_Percentage__c) are set by the calling test, keeping
 * 00-foundation free of upstream schema dependencies.
 */
@IsTest
public class TestDataFactory {
    private static Integer counter = 1;

    public static User createTestUser(String profileName, String roleDeveloperName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        Id roleId = null;
        if (String.isNotBlank(roleDeveloperName)) {
            roleId = [SELECT Id FROM UserRole WHERE DeveloperName = :roleDeveloperName LIMIT 1].Id;
        }
        String uniqueKey = 'nexus' + counter++ + '.' + System.currentTimeMillis() + '@testorg.nexuscore.dev';
        return new User(
            Alias = 'nxtest',
            Email = uniqueKey,
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Nexus',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            UserRoleId = roleId,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueKey
        );
    }

    public static List<Account> createAccounts(Integer count, Boolean doInsert) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = 'Test Account ' + counter++, Industry = 'Technology'));
        }
        if (doInsert) {
            insert accounts;
        }
        return accounts;
    }

    public static List<Contact> createContacts(Id accountId, Integer count, Boolean doInsert) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            contacts.add(new Contact(AccountId = accountId, FirstName = 'Test', LastName = 'Contact ' + counter++));
        }
        if (doInsert) {
            insert contacts;
        }
        return contacts;
    }

    public static List<Opportunity> createOpportunities(Id accountId, Integer count, Boolean doInsert) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            opps.add(
                new Opportunity(
                    Name = 'Test Opportunity ' + counter++,
                    AccountId = accountId,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30),
                    Amount = 10000
                )
            );
        }
        if (doInsert) {
            insert opps;
        }
        return opps;
    }

    public static Id getFakeId(Schema.SObjectType sObjectType) {
        String keyPrefix = sObjectType.getDescribe().getKeyPrefix();
        String suffix = String.valueOf(counter++);
        return (Id) (keyPrefix + '0'.repeat(12 - suffix.length()) + suffix);
    }
}
