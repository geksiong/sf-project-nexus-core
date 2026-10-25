/**
 * @description Selector for Nebula Logger log entries surfaced in the Admin Cockpit error feed.
 */
public virtual with sharing class LogEntriesSelector {
    @TestVisible
    private static LogEntriesSelector instance;

    /** @description Returns the selector; tests replace it with a Test.createStub() mock via `instance`. */
    public static LogEntriesSelector newInstance() {
        if (instance == null) {
            instance = new LogEntriesSelector();
        }
        return instance;
    }

    public virtual List<LogEntry__c> selectRecentByLevels(Set<String> loggingLevels, Integer maxRows) {
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
