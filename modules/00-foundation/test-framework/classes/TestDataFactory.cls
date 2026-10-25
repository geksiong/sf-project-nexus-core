@IsTest
public class TestDataFactory {
    private static Integer counter = 1;
    public static User createTestUser(String profileName, String roleDeveloperName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName WITH USER_MODE LIMIT 1];
        UserRole r = [SELECT Id FROM UserRole WHERE DeveloperName = :roleDeveloperName WITH USER_MODE LIMIT 1];
        String uniqueKey = 'nexus' + counter++ + '@testorg.com';
        return new User(
            Alias = 'nxtest', Email = uniqueKey, EmailEncodingKey = 'UTF-8',
            LastName = 'Testing', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, UserRoleId = r.Id, TimeZoneSidKey = 'America/Los_Angeles',
            UserName = uniqueKey
        );
    }
    public static Id getFakeId(Schema.SObjectType sObjectType) {
        String keyPrefix = sObjectType.getDescribe().getKeyPrefix();
        return (Id) (keyPrefix + '000000000000'.substring(0, 12 - String.valueOf(counter).length()) + counter++);
    }
}