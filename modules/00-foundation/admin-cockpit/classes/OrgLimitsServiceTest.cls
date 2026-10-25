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
        // Standard users without LoggerLogViewer cannot read LogEntry__c in user mode.
        Assert.isFalse(payload.errorFeedAvailable);
        Assert.isTrue(payload.errorFeedMessage.startsWith('Error feed unavailable'));
        Assert.isTrue(payload.recentErrors.isEmpty());
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
