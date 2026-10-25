/**
 * @description Native Apex service querying System.OrgLimits without external HTTP callouts.
 * Feeds the adminLimitsCockpit LWC with org resource telemetry and the Nebula Logger error feed.
 * Not cacheable: every call returns live numbers, and caught failures can be logged.
 */
public with sharing class OrgLimitsService {
    public static final String STATUS_OK = 'OK';
    public static final String STATUS_WARNING = 'WARNING';
    public static final String STATUS_CRITICAL = 'CRITICAL';

    @TestVisible
    private static final Decimal WARNING_THRESHOLD = 70;
    @TestVisible
    private static final Decimal CRITICAL_THRESHOLD = 85;
    private static final Integer ERROR_FEED_SIZE = 10;
    private static final Set<String> ERROR_FEED_LEVELS = new Set<String>{ 'ERROR', 'WARN' };
    @TestVisible
    private static final String ERROR_FEED_NO_ACCESS = 'Error feed unavailable: assign the LoggerLogViewer (or LoggerAdmin) permission set to view Nebula Logger entries.';

    // Ordered list of monitored limits: System.OrgLimits key => display label
    private static final List<List<String>> MONITORED_LIMITS = new List<List<String>>{
        new List<String>{ 'DailyApiRequests', 'Daily API Requests' },
        new List<String>{ 'DailyAsyncApexExecutions', 'Daily Async Apex Executions' },
        new List<String>{ 'DailyBulkV2QueryJobs', 'Daily Bulk API 2.0 Query Jobs' },
        new List<String>{ 'DataStorageMB', 'Data Storage (MB)' },
        new List<String>{ 'FileStorageMB', 'File Storage (MB)' },
        new List<String>{ 'SingleEmail', 'Daily Single Emails' },
        new List<String>{ 'HourlyPublishedPlatformEvents', 'Hourly Published Platform Events' },
        new List<String>{ 'DailyStandardVolumePlatformEvents', 'Daily Standard-Volume Platform Events' }
    };

    public class LimitItem {
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public Integer current { get; set; }
        @AuraEnabled
        public Integer max { get; set; }
        @AuraEnabled
        public Decimal percentUsed { get; set; }
        @AuraEnabled
        public String status { get; set; }
    }
    public class LogSummaryItem {
        @AuraEnabled
        public String logId { get; set; }
        @AuraEnabled
        public String message { get; set; }
        @AuraEnabled
        public String origin { get; set; }
        @AuraEnabled
        public Datetime loggedTime { get; set; }
        @AuraEnabled
        public String severity { get; set; }
    }
    public class CockpitPayload {
        @AuraEnabled
        public String overallStatus { get; set; }
        @AuraEnabled
        public Datetime generatedAt { get; set; }
        @AuraEnabled
        public List<LimitItem> limits { get; set; }
        @AuraEnabled
        public List<LogSummaryItem> recentErrors { get; set; }
        @AuraEnabled
        public Boolean errorFeedAvailable { get; set; }
        @AuraEnabled
        public String errorFeedMessage { get; set; }
    }

    @AuraEnabled
    public static CockpitPayload getAdminCockpitSnapshot() {
        CockpitPayload payload = new CockpitPayload();
        payload.generatedAt = System.now();
        payload.limits = buildLimitItems(System.OrgLimits.getMap());
        payload.overallStatus = resolveOverallStatus(payload.limits);
        payload.recentErrors = new List<LogSummaryItem>();
        payload.errorFeedAvailable = true;

        if (!hasErrorFeedAccess()) {
            // Expected for non-log-viewers: report it without an exception or a log entry per page load.
            payload.errorFeedAvailable = false;
            payload.errorFeedMessage = ERROR_FEED_NO_ACCESS;
            return payload;
        }

        try {
            for (
                LogEntry__c entry : LogEntriesSelector.newInstance()
                    .selectRecentByLevels(ERROR_FEED_LEVELS, ERROR_FEED_SIZE)
            ) {
                LogSummaryItem logItem = new LogSummaryItem();
                logItem.logId = entry.Id;
                logItem.message = entry.Message__c;
                logItem.origin = entry.OriginLocation__c;
                logItem.loggedTime = entry.Timestamp__c;
                logItem.severity = entry.LoggingLevel__c;
                payload.recentErrors.add(logItem);
            }
        } catch (Exception ex) {
            payload.errorFeedAvailable = false;
            payload.errorFeedMessage = 'Error feed unavailable: ' + ex.getMessage();
            Logger.error('Admin Cockpit failed to read the Nebula Logger error feed', ex);
            Logger.saveLog();
        }
        return payload;
    }

    /** @description Object and field read access needed by LogEntriesSelector (granted by LoggerLogViewer). */
    @TestVisible
    private static Boolean hasErrorFeedAccess() {
        return Schema.SObjectType.LogEntry__c.isAccessible() &&
            Schema.SObjectType.LogEntry__c.fields.Message__c.isAccessible() &&
            Schema.SObjectType.LogEntry__c.fields.LoggingLevel__c.isAccessible() &&
            Schema.SObjectType.LogEntry__c.fields.OriginLocation__c.isAccessible() &&
            Schema.SObjectType.LogEntry__c.fields.Timestamp__c.isAccessible();
    }

    @TestVisible
    private static List<LimitItem> buildLimitItems(Map<String, System.OrgLimit> limitsMap) {
        List<LimitItem> items = new List<LimitItem>();
        for (List<String> monitored : MONITORED_LIMITS) {
            System.OrgLimit orgLimit = limitsMap.get(monitored[0]);
            if (orgLimit == null) {
                continue;
            }
            LimitItem item = new LimitItem();
            item.name = monitored[0];
            item.label = monitored[1];
            item.current = orgLimit.getValue();
            item.max = orgLimit.getLimit();
            item.percentUsed = calculatePercent(item.current, item.max);
            item.status = resolveStatus(item.percentUsed);
            items.add(item);
        }
        return items;
    }

    @TestVisible
    private static Decimal calculatePercent(Integer current, Integer max) {
        if (max == null || max <= 0 || current == null) {
            return 0;
        }
        return (Decimal.valueOf(current) / max * 100).setScale(1);
    }

    /** @description OK (< 70%), WARNING (70% - 85%), CRITICAL (> 85%). */
    @TestVisible
    private static String resolveStatus(Decimal percentUsed) {
        if (percentUsed > CRITICAL_THRESHOLD) {
            return STATUS_CRITICAL;
        }
        if (percentUsed >= WARNING_THRESHOLD) {
            return STATUS_WARNING;
        }
        return STATUS_OK;
    }

    @TestVisible
    private static String resolveOverallStatus(List<LimitItem> items) {
        String overall = STATUS_OK;
        for (LimitItem item : items) {
            if (item.status == STATUS_CRITICAL) {
                return STATUS_CRITICAL;
            }
            if (item.status == STATUS_WARNING) {
                overall = STATUS_WARNING;
            }
        }
        return overall;
    }
}
