@IsTest
private class SalesEngineSelectorsTest {
    @IsTest
    static void emptyInputsShortCircuitWithoutQuerying() {
        Assert.isTrue(OpportunitiesSelector.newInstance().selectByIdWithDetails(new Set<Id>()).isEmpty());
        Assert.isTrue(OpportunitiesSelector.newInstance().selectByIdWithDetails(null).isEmpty());
        Assert.isTrue(AccountsSelector.newInstance().selectByIdWithCreditStatus(new Set<Id>()).isEmpty());
        Assert.isTrue(AccountsSelector.newInstance().selectByIdWithCreditStatus(null).isEmpty());
        Assert.isTrue(UsersSelector.newInstance().selectByIdWithManagerChain(new Set<Id>()).isEmpty());
        Assert.isTrue(UsersSelector.newInstance().selectByIdWithManagerChain(null).isEmpty());
        Assert.areEqual(0, Limits.getQueries(), 'Empty inputs must not consume SOQL queries');
    }

    @IsTest
    static void userSelectorReturnsManagerChain() {
        Map<Id, User> users = UsersSelector.newInstance()
            .selectByIdWithManagerChain(new Set<Id>{ UserInfo.getUserId() });
        Assert.isTrue(users.containsKey(UserInfo.getUserId()));
    }
}
