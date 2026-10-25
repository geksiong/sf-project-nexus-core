@IsTest
private class ServiceDeskDmlTest {
    /** @description Side-effect DML failures are logged (Admin Cockpit error feed), not swallowed. */
    @IsTest
    static void failedRowsAreLoggedAsErrors() {
        Test.startTest();
        ServiceDeskDml.save(
            Database.insert(new List<CaseComment>{ new CaseComment(CommentBody = 'No parent') }, false),
            'Probe operation'
        );
        Test.stopTest();

        List<LogEntry__c> entries = [
            SELECT LoggingLevel__c, Message__c
            FROM LogEntry__c
            WHERE LoggingLevel__c = 'ERROR'
        ];
        Assert.areEqual(1, entries.size(), String.valueOf(entries));
        Assert.areEqual('ERROR', entries[0].LoggingLevel__c);
        Assert.isTrue(
            entries[0].Message__c.startsWith('Probe operation failed: REQUIRED_FIELD_MISSING'),
            entries[0].Message__c
        );
    }

    @IsTest
    static void successfulRowsLogNothing() {
        ServiceDeskDml.save(new List<Database.SaveResult>(), 'Probe operation');
        Assert.areEqual(0, Logger.getBufferSize());
    }
}
