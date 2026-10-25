@IsTest
private class OrgLimitsServiceTest {
    @IsTest
    static void snapshotReturnsLiveLimitsAndFeed() {
        Test.startTest();
        OrgLimitsService.CockpitPayload payload = OrgLimitsService.getAdminCockpitSnapshot();
        Test.stopTest();

        Assert.isNotNull(payload.generatedAt);
        Assert.isFalse(payload.limits.isEmpty(), 'At least one monitored org limit should be returned');
        Assert.isNotNull(payload.overallStatus);
        Assert.isNotNull(payload.recentErrors);
        for (OrgLimitsService.LimitItem item : payload.limits) {
            Assert.isTrue(item.max >= 0);
            Assert.isNotNull(item.status);
        }
    }

    @IsTest
    static void statusThresholdsMatchCockpitStandard() {
        Assert.areEqual('OK', OrgLimitsService.resolveStatus(0));
        Assert.areEqual('OK', OrgLimitsService.resolveStatus(69.9));
        Assert.areEqual('WARNING', OrgLimitsService.resolveStatus(70));
        Assert.areEqual('WARNING', OrgLimitsService.resolveStatus(85));
        Assert.areEqual('CRITICAL', OrgLimitsService.resolveStatus(85.1));
        Assert.areEqual('CRITICAL', OrgLimitsService.resolveStatus(100));
    }

    @IsTest
    static void percentCalculationHandlesZeroMax() {
        Assert.areEqual(0, OrgLimitsService.calculatePercent(5, 0));
        Assert.areEqual(0, OrgLimitsService.calculatePercent(null, 10));
        Assert.areEqual(33.3, OrgLimitsService.calculatePercent(1, 3));
    }

    @IsTest
    static void overallStatusIsWorstLimitStatus() {
        Assert.areEqual('OK', OrgLimitsService.resolveOverallStatus(new List<OrgLimitsService.LimitItem>()));
        Assert.areEqual('WARNING', OrgLimitsService.resolveOverallStatus(items(new List<String>{ 'OK', 'WARNING' })));
        Assert.areEqual(
            'CRITICAL',
            OrgLimitsService.resolveOverallStatus(items(new List<String>{ 'WARNING', 'CRITICAL', 'OK' }))
        );
    }

    @IsTest
    static void feedFailureIsReportedNotHidden() {
        User noAccessUser = TestDataFactory.createTestUser('Standard User', null);
        insert noAccessUser;

        OrgLimitsService.CockpitPayload payload;
        System.runAs(noAccessUser) {
            payload = OrgLimitsService.getAdminCockpitSnapshot();
        }
        // Standard users without LoggerLogViewer cannot read LogEntry__c.
        Assert.isFalse(payload.errorFeedAvailable);
        Assert.areEqual(OrgLimitsService.ERROR_FEED_NO_ACCESS, payload.errorFeedMessage);
        Assert.isTrue(payload.recentErrors.isEmpty());
        Assert.areEqual(0, Logger.getBufferSize(), 'Missing access is expected and must not be logged');
        Assert.isFalse(payload.limits.isEmpty(), 'Limits are still returned without log access');
    }

    @IsTest
    static void feedMapsErrorAndWarnEntriesFromSelector() {
        Datetime loggedAt = Datetime.now();
        TestStub logEntries = new TestStub()
            .returns(
                'selectRecentByLevels',
                new List<LogEntry__c>{
                    new LogEntry__c(
                        Id = TestDataFactory.getFakeId(LogEntry__c.SObjectType),
                        Message__c = 'Simulated cockpit error',
                        LoggingLevel__c = 'ERROR',
                        OriginLocation__c = 'SampleService.execute',
                        Timestamp__c = loggedAt
                    ),
                    new LogEntry__c(
                        Id = TestDataFactory.getFakeId(LogEntry__c.SObjectType),
                        Message__c = 'Simulated cockpit warning',
                        LoggingLevel__c = 'WARN',
                        Timestamp__c = loggedAt
                    )
                }
            );
        LogEntriesSelector.instance = (LogEntriesSelector) logEntries.create(LogEntriesSelector.class);

        OrgLimitsService.CockpitPayload payload = OrgLimitsService.getAdminCockpitSnapshot();

        Assert.isTrue(payload.errorFeedAvailable, 'Feed should be available: ' + payload.errorFeedMessage);
        Assert.areEqual(2, payload.recentErrors.size());
        OrgLimitsService.LogSummaryItem first = payload.recentErrors[0];
        Assert.areEqual('Simulated cockpit error', first.message);
        Assert.areEqual('ERROR', first.severity);
        Assert.areEqual('SampleService.execute', first.origin);
        Assert.areEqual(loggedAt, first.loggedTime);
        Assert.isNotNull(first.logId);

        List<Object> args = logEntries.lastArguments('selectRecentByLevels');
        Assert.areEqual(new Set<String>{ 'ERROR', 'WARN' }, (Set<String>) args[0], 'Feed shows ERROR and WARN only');
        Assert.areEqual(10, (Integer) args[1], 'Feed is capped at 10 entries');
    }

    private static List<OrgLimitsService.LimitItem> items(List<String> statuses) {
        List<OrgLimitsService.LimitItem> result = new List<OrgLimitsService.LimitItem>();
        for (String status : statuses) {
            OrgLimitsService.LimitItem item = new OrgLimitsService.LimitItem();
            item.status = status;
            result.add(item);
        }
        return result;
    }
}
