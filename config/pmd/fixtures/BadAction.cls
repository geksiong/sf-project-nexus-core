public with sharing class BadAction {
    public class Result { @InvocableVariable public Boolean isSuccess; }
    @InvocableMethod(label='Bad')
    public static List<Result> run(List<String> s) { return null; }
}
