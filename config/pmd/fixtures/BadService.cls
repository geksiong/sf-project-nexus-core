public with sharing class BadService {
    public static List<Account> load() {
        List<Account> a = [SELECT Id FROM Account];
        List<Account> b = Database.query('SELECT Id FROM Account WITH USER_MODE');
        return a;
    }
}
