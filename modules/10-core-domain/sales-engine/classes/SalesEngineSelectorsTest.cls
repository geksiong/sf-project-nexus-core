@IsTest
private class SalesEngineSelectorsTest {
    @IsTest
    static void emptyInputsShortCircuitWithoutQuerying() {
        Assert.isTrue(OpportunitiesSelector.selectByIdWithDetails(new Set<Id>()).isEmpty());
        Assert.isTrue(OpportunitiesSelector.selectByIdWithDetails(null).isEmpty());
        Assert.isTrue(AccountsSelector.selectByIdWithCreditStatus(new Set<Id>()).isEmpty());
        Assert.isTrue(AccountsSelector.selectByIdWithCreditStatus(null).isEmpty());
        Assert.isTrue(UsersSelector.selectByIdWithManagerChain(new Set<Id>()).isEmpty());
        Assert.isTrue(UsersSelector.selectByIdWithManagerChain(null).isEmpty());
        Assert.areEqual(0, Limits.getQueries(), 'Empty inputs must not consume SOQL queries');
    }

    @IsTest
    static void userSelectorReturnsManagerChain() {
        Map<Id, User> users = UsersSelector.selectByIdWithManagerChain(new Set<Id>{ UserInfo.getUserId() });
        Assert.isTrue(users.containsKey(UserInfo.getUserId()));
    }
}
