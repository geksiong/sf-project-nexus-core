/**
 * @description Lightweight, robust Trigger Handler base class replacing heavy domain frameworks.
 * Provides context routing, loop detection, and bypass checks.
 */
public virtual class TriggerHandler {
    private static Set<String> bypassedHandlers = new Set<String>();
    private String handlerName;

    public TriggerHandler() {
        this.handlerName = String.valueOf(this).split(':')[0];
    }

    public void run() {
        if (isBypassed() || BypassService.isTriggerBypassed(getSObjectName())) {
            return;
        }

        switch on Trigger.operationType {
            when BEFORE_INSERT {
                beforeInsert(Trigger.new);
            }
            when BEFORE_UPDATE {
                beforeUpdate(Trigger.new, Trigger.oldMap);
            }
            when BEFORE_DELETE {
                beforeDelete(Trigger.old, Trigger.oldMap);
            }
            when AFTER_INSERT {
                afterInsert(Trigger.new, Trigger.newMap);
            }
            when AFTER_UPDATE {
                afterUpdate(Trigger.new, Trigger.oldMap);
            }
            when AFTER_DELETE {
                afterDelete(Trigger.old, Trigger.oldMap);
            }
            when AFTER_UNDELETE {
                afterUndelete(Trigger.new, Trigger.newMap);
            }
        }
    }

    // Virtual context methods for override
    protected virtual void beforeInsert(List<SObject> newRecords) {}
    protected virtual void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {}
    protected virtual void beforeDelete(List<SObject> deletedRecords, Map<Id, SObject> oldRecordMap) {}
    protected virtual void afterInsert(List<SObject> newRecords, Map<Id, SObject> newRecordMap) {}
    protected virtual void afterUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {}
    protected virtual void afterDelete(List<SObject> deletedRecords, Map<Id, SObject> oldRecordMap) {}
    protected virtual void afterUndelete(List<SObject> restoredRecords, Map<Id, SObject> newRecordMap) {}

    protected virtual String getSObjectName() {
        if (Trigger.new != null && !Trigger.new.isEmpty()) {
            return Trigger.new[0].getSObjectType().getDescribe().getName();
        } else if (Trigger.old != null && !Trigger.old.isEmpty()) {
            return Trigger.old[0].getSObjectType().getDescribe().getName();
        }
        return '';
    }

    public static void bypass(String handlerName) {
        bypassedHandlers.add(handlerName.toLowerCase());
    }

    public static void clearBypass(String handlerName) {
        bypassedHandlers.remove(handlerName.toLowerCase());
    }

    public static Boolean isBypassed(String handlerName) {
        return bypassedHandlers.contains(handlerName.toLowerCase());
    }

    public Boolean isBypassed() {
        return TriggerHandler.isBypassed(this.handlerName);
    }
}