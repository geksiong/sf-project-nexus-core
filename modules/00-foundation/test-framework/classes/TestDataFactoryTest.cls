@IsTest
private class TestDataFactoryTest {
    @IsTest
    static void buildsRelatedSalesRecords() {
        Account acc = TestDataFactory.createAccounts(1, true)[0];
        List<Contact> contacts = TestDataFactory.createContacts(acc.Id, 2, true);
        List<Opportunity> opps = TestDataFactory.createOpportunities(acc.Id, 3, true);

        Assert.areEqual(2, contacts.size());
        Assert.areEqual(3, opps.size());
        Assert.isNotNull(opps[0].Id);
        Assert.areEqual(acc.Id, opps[0].AccountId);
    }

    @IsTest
    static void buildsUnsavedUserWithoutRole() {
        User u = TestDataFactory.createTestUser('Standard User', null);
        Assert.isNull(u.Id);
        Assert.isNull(u.UserRoleId);
        Assert.isTrue(u.Username.endsWith('@testorg.nexuscore.dev'));
    }

    @IsTest
    static void generatesValidFakeIds() {
        Id fakeId = TestDataFactory.getFakeId(Account.SObjectType);
        Assert.areEqual(Account.SObjectType, fakeId.getSObjectType());
        Assert.areNotEqual(fakeId, TestDataFactory.getFakeId(Account.SObjectType));
    }
}
