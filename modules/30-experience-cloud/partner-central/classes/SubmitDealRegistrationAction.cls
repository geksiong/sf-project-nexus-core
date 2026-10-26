/**
 * @description Headless action that registers a partner deal. Used by the Partner_Deal_Registration flow in
 * Nexus Partner Central; reusable by Agentforce / MCP via the uniform result envelope.
 */
public with sharing class SubmitDealRegistrationAction {
    public class Request {
        @InvocableVariable(required=true label='Customer Company')
        public String customerCompany;
        @InvocableVariable(label='Customer Contact Name')
        public String customerContactName;
        @InvocableVariable(label='Customer Email')
        public String customerEmail;
        @InvocableVariable(required=true label='Estimated Amount')
        public Decimal estimatedAmount;
        @InvocableVariable(required=true label='Expected Close Date')
        public Date expectedCloseDate;
        @InvocableVariable(
            label='Product Interest'
            description='IoT Platform, Field Service, Analytics or Professional Services'
        )
        public String productInterest;
    }
    public class Result {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        @InvocableVariable(label='Error Code')
        public String errorCode;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='Payload')
        public OutputPayload payload;
    }
    public class OutputPayload {
        @InvocableVariable
        public Id dealRegistrationId;
        @InvocableVariable
        public String status;
    }
    @InvocableMethod(
        label='Submit Deal Registration'
        description='Registers a partner deal and routes it to the channel manager for approval.'
        category='Partner'
    )
    public static List<Result> execute(List<Request> requests) {
        return DealRegistrationService.submitRegistrations(requests);
    }
}
