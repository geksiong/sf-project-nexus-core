public with sharing class MixedSelector {
    public static List<Account> compliant() {
        return [SELECT Id FROM Account WITH USER_MODE LIMIT 10];
    }
    public static List<Account> missingUserMode() {
        return [SELECT Id FROM Account LIMIT 10];
    }
}
