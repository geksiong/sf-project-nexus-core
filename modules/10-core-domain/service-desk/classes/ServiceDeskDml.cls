/**
 * @description Logs the failures of partial-success (allOrNone = false) DML performed as a side effect
 * of a case change, so one bad row neither blocks the agent's save nor disappears silently.
 */
public with sharing class ServiceDeskDml {
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
