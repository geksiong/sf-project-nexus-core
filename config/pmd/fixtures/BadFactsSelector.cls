public virtual with sharing class BadFactsSelector {
    public virtual List<Account> userMode() {
        return [SELECT Id FROM Account WITH USER_MODE LIMIT 10];
    }
    public virtual List<Account> implicitMode() {
        return [SELECT Id FROM Account LIMIT 10];
    }
}
