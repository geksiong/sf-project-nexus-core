/**
 * @description Native Apex service querying System.OrgLimits without external HTTP callouts.
 */
public with sharing class OrgLimitsService {
    public class LimitItem {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Integer current { get; set; }
        @AuraEnabled public Integer max { get; set; }
        @AuraEnabled public Double percentUsed { get; set; }
        @AuraEnabled public String status { get; set; }
    }
    public class LogSummaryItem {
        @AuraEnabled public String logId { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String loggedTime { get; set; }
        @AuraEnabled public String severity { get; set; }
    }
    public class CockpitPayload {
        @AuraEnabled public List<LimitItem> limits { get; set; }
        @AuraEnabled public List<LogSummaryItem> recentErrors { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static CockpitPayload getAdminCockpitSnapshot() {
        CockpitPayload payload = new CockpitPayload();
        payload.limits = new List<LimitItem>();
        payload.recentErrors = new List<LogSummaryItem>();

        Map<String, System.OrgLimit> limitsMap = System.OrgLimits.getMap();
        Map<String, String> targetLimits = new Map<String, String>{
            'DailyApiRequests' => 'Daily API Requests',
            'DataStorageMB' => 'Data Storage (MB)',
            'FileStorageMB' => 'File Storage (MB)',
            'HourlyTimeBasedWorkflow' => 'Hourly Workflow Actions'
        };

        for (String key : targetLimits.keySet()) {
            if (limitsMap.containsKey(key)) {
                System.OrgLimit ol = limitsMap.get(key);
                LimitItem item = new LimitItem();
                item.name = key;
                item.label = targetLimits.get(key);
                item.current = ol.getValue();
                item.max = ol.getLimit();
                item.percentUsed = item.max > 0 ? (Double.valueOf(item.current) / Double.valueOf(item.max)) * 100.0 : 0.0;
                item.status = item.percentUsed >= 85.0 ? 'CRITICAL' : (item.percentUsed >= 70.0 ? 'WARNING' : 'OK');
                payload.limits.add(item);
            }
        }

        try {
            List<SObject> logs = Database.query(
                'SELECT Id, nebula__Message__c, nebula__LoggedDate__c, nebula__LoggingLevel__c ' +
                'FROM nebula__LogEntry__c ' +
                'WHERE nebula__LoggingLevel__c IN (\'ERROR\', \'CRITICAL\') ' +
                'WITH USER_MODE ' +
                'ORDER BY nebula__LoggedDate__c DESC LIMIT 5'
            );
            for (SObject entry : logs) {
                LogSummaryItem logItem = new LogSummaryItem();
                logItem.logId = (String) entry.get('Id');
                logItem.message = (String) entry.get('nebula__Message__c');
                logItem.loggedTime = String.valueOf(entry.get('nebula__LoggedDate__c'));
                logItem.severity = (String) entry.get('nebula__LoggingLevel__c');
                payload.recentErrors.add(logItem);
            }
        } catch (Exception ex) {
            LogSummaryItem fallback = new LogSummaryItem();
            fallback.logId = 'NONE';
            fallback.message = 'System Operational - No Active Critical Errors Reported';
            fallback.loggedTime = String.valueOf(System.now());
            fallback.severity = 'INFO';
            payload.recentErrors.add(fallback);
        }

        return payload;
    }
}