/**
 * @description Logs the failures of partial-success (allOrNone = false) DML performed as a side effect
 * (trigger side effects, event consumers, async jobs), so one bad row neither blocks the main save nor
 * disappears silently: every failure reaches the Admin Cockpit error feed.
 */
public with sharing class PartialDml {
    public static void save(List<Database.SaveResult> results, String operation) {
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                List<String> messages = new List<String>();
                for (Database.Error err : result.getErrors()) {
                    messages.add(err.getStatusCode() + ': ' + err.getMessage());
                }
                Logger.error(operation + ' failed: ' + String.join(messages, ' '));
            }
        }
        if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
    }
}
