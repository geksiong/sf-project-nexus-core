/**
 * @description Selector for Nebula Logger log entries surfaced in the Admin Cockpit error feed.
 */
public with sharing class LogEntriesSelector {
    public static List<LogEntry__c> selectRecentByLevels(Set<String> loggingLevels, Integer maxRows) {
        return [
            SELECT Id, Message__c, LoggingLevel__c, OriginLocation__c, Timestamp__c
            FROM LogEntry__c
            WHERE LoggingLevel__c IN :loggingLevels
            WITH USER_MODE
            ORDER BY Timestamp__c DESC
            LIMIT :maxRows
        ];
    }
}
