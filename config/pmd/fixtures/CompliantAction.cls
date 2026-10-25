public with sharing class CompliantAction {
    public class Result {
        @InvocableVariable
        public Boolean isSuccess;
        @InvocableVariable
        public String errorCode;
        @InvocableVariable
        public String errorMessage;
        @InvocableVariable
        public Payload payload;
    }
    public class Payload {
        @InvocableVariable
        public String value;
    }
    @InvocableMethod(label='Compliant')
    public static List<Result> execute(List<String> inputs) {
        return new List<Result>();
    }
}
