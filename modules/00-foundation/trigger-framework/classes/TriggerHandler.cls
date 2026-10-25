/**
 * @description Lightweight, robust Trigger Handler base class replacing heavy domain frameworks.
 * Provides context routing, recursion (loop) guards, and bypass checks.
 *
 * Usage: a trigger body is a single line - `new OpportunityTriggerHandler().run();`
 * Subclasses override only the context methods they need and delegate to Domain Services.
 */
public virtual class TriggerHandler {
    private static Set<String> bypassedHandlers = new Set<String>();
    private static Map<String, LoopCount> loopCountByHandler = new Map<String, LoopCount>();

    private String handlerName;

    @TestVisible
    private System.TriggerOperation context;
    @TestVisible
    private Boolean isTriggerExecuting;
    @TestVisible
    private List<SObject> newRecords;
    @TestVisible
    private List<SObject> oldRecords;
    @TestVisible
    private Map<Id, SObject> newRecordMap;
    @TestVisible
    private Map<Id, SObject> oldRecordMap;

    public TriggerHandler() {
        this.handlerName = String.valueOf(this).split(':')[0];
        this.context = Trigger.operationType;
        this.isTriggerExecuting = Trigger.isExecuting;
        this.newRecords = Trigger.new;
        this.oldRecords = Trigger.old;
        this.newRecordMap = Trigger.newMap;
        this.oldRecordMap = Trigger.oldMap;
    }

    public void run() {
        if (!isTriggerExecuting || context == null) {
            throw new TriggerHandlerException('Trigger handler called outside of trigger execution');
        }
        if (isBypassed() || BypassService.isTriggerBypassed(getSObjectName()) || isLoopLimitExceeded()) {
            return;
        }

        switch on context {
            when BEFORE_INSERT {
                beforeInsert(newRecords);
            }
            when BEFORE_UPDATE {
                beforeUpdate(newRecords, oldRecordMap);
            }
            when BEFORE_DELETE {
                beforeDelete(oldRecords, oldRecordMap);
            }
            when AFTER_INSERT {
                afterInsert(newRecords, newRecordMap);
            }
            when AFTER_UPDATE {
                afterUpdate(newRecords, oldRecordMap);
            }
            when AFTER_DELETE {
                afterDelete(oldRecords, oldRecordMap);
            }
            when AFTER_UNDELETE {
                afterUndelete(newRecords, newRecordMap);
            }
        }
    }

    // Virtual context methods for override
    protected virtual void beforeInsert(List<SObject> newRecords) {
    }
    protected virtual void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
    }
    protected virtual void beforeDelete(List<SObject> deletedRecords, Map<Id, SObject> oldRecordMap) {
    }
    protected virtual void afterInsert(List<SObject> newRecords, Map<Id, SObject> newRecordMap) {
    }
    protected virtual void afterUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
    }
    protected virtual void afterDelete(List<SObject> deletedRecords, Map<Id, SObject> oldRecordMap) {
    }
    protected virtual void afterUndelete(List<SObject> restoredRecords, Map<Id, SObject> newRecordMap) {
    }

    protected virtual String getSObjectName() {
        if (newRecords != null && !newRecords.isEmpty()) {
            return newRecords[0].getSObjectType().getDescribe().getName();
        } else if (oldRecords != null && !oldRecords.isEmpty()) {
            return oldRecords[0].getSObjectType().getDescribe().getName();
        }
        return '';
    }

    /**
     * @description Caps how many times this handler may run per transaction for the current
     * trigger context. Once exceeded, further invocations are skipped silently (recursion guard).
     */
    public void setMaxLoopCount(Integer max) {
        String key = loopKey();
        if (!loopCountByHandler.containsKey(key)) {
            loopCountByHandler.put(key, new LoopCount(max));
        } else {
            loopCountByHandler.get(key).max = max;
        }
    }

    public void clearMaxLoopCount() {
        loopCountByHandler.remove(loopKey());
    }

    private Boolean isLoopLimitExceeded() {
        String key = loopKey();
        if (!loopCountByHandler.containsKey(key)) {
            return false;
        }
        return loopCountByHandler.get(key).increment();
    }

    private String loopKey() {
        return handlerName + ':' + String.valueOf(context);
    }

    public static void bypass(String handlerName) {
        bypassedHandlers.add(handlerName.toLowerCase());
    }

    public static void clearBypass(String handlerName) {
        bypassedHandlers.remove(handlerName.toLowerCase());
    }

    public static void clearAllBypasses() {
        bypassedHandlers.clear();
    }

    public static Boolean isBypassed(String handlerName) {
        return bypassedHandlers.contains(handlerName.toLowerCase());
    }

    public Boolean isBypassed() {
        return TriggerHandler.isBypassed(this.handlerName);
    }

    private class LoopCount {
        private Integer max;
        private Integer count = 0;

        private LoopCount(Integer max) {
            this.max = max;
        }

        /** @return true when the increment pushes the count past the configured max */
        private Boolean increment() {
            count++;
            return count > max;
        }
    }

    public class TriggerHandlerException extends Exception {
    }
}
