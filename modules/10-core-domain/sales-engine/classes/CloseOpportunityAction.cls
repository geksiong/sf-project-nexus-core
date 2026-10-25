/**
 * @description Headless action that closes an Opportunity as Won or Lost. Used by the
 * Opportunity Deal Closer screen flow; reusable by Agentforce / MCP via the uniform result envelope.
 */
public with sharing class CloseOpportunityAction {
    public class Request {
        @InvocableVariable(required=true label='Opportunity Id')
        public Id opportunityId;
        @InvocableVariable(required=true label='Outcome' description='Won or Lost')
        public String outcome;
        @InvocableVariable(
            label='Primary Contact Id'
            description='Won only: contact to mark as the primary contact role'
        )
        public String primaryContactId;
        @InvocableVariable(label='Loss Reason' description='Lost only: value of Opportunity.Loss_Reason__c')
        public String lossReason;
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
        public Id opportunityId;
        @InvocableVariable
        public String stageName;
    }
    @InvocableMethod(
        label='Close Opportunity'
        description='Closes an opportunity as Won or Lost, enforcing sales engine stage gates.'
        category='Sales'
    )
    public static List<Result> execute(List<Request> requests) {
        return OpportunityService.closeDeals(requests);
    }
}
