@IsTest
private class TestStubTest {
    // Test.createStub() cannot mock inner classes, so a real top-level selector is used.
    @IsTest
    static void returnsCannedResponsesAndRecordsCalls() {
        List<LogEntry__c> canned = new List<LogEntry__c>{ new LogEntry__c(Message__c = 'Stubbed') };
        TestStub stub = new TestStub().returns('selectRecentByLevels', canned);
        LogEntriesSelector selector = (LogEntriesSelector) stub.create(LogEntriesSelector.class);

        Assert.areEqual(0, stub.callCount('selectRecentByLevels'));
        Assert.isNull(stub.lastArguments('selectRecentByLevels'));
        Assert.areEqual(canned, selector.selectRecentByLevels(new Set<String>{ 'ERROR' }, 5));
        selector.selectRecentByLevels(new Set<String>{ 'WARN' }, 7);
        Assert.areEqual(2, stub.callCount('SELECTRECENTBYLEVELS'), 'Method names are case-insensitive');
        Assert.areEqual(7, stub.lastArguments('selectRecentByLevels')[1]);
        Assert.areEqual(0, Limits.getQueries(), 'Stubbed selectors never query');
    }

    @IsTest
    static void unconfiguredMethodsReturnNull() {
        LogEntriesSelector selector = (LogEntriesSelector) new TestStub().create(LogEntriesSelector.class);
        Assert.isNull(selector.selectRecentByLevels(new Set<String>{ 'ERROR' }, 1));
    }
}
