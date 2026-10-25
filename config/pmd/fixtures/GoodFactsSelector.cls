public virtual without sharing class GoodFactsSelector {
    public virtual Set<Id> selectHeld(Set<Id> ids) {
        return new Map<Id, Account>([SELECT Id FROM Account WHERE Id IN :ids WITH SYSTEM_MODE]).keySet();
    }
}
