/**
 * @description Headless action that escalates a case to Tier 2. Used by the Escalate Case screen flow;
 * reusable by Agentforce / MCP via the uniform result envelope.
 */
public with sharing class EscalateCaseAction {
    public class Request {
        @InvocableVariable(required=true label='Case Id')
        public Id caseId;
        @InvocableVariable(required=true label='Escalation Reason' description='Why the case needs Tier 2')
        public String reason;
        @InvocableVariable(
            label='Technical SME User Id'
            description='Optional: user to add to the case team as Technical SME'
        )
        public String smeUserId;
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
        public Id caseId;
        @InvocableVariable
        public String caseNumber;
        @InvocableVariable
        public String status;
    }
    @InvocableMethod(
        label='Escalate Case'
        description='Escalates a case to the Tier 2 queue with a reason and optional Technical SME.'
        category='Service'
    )
    public static List<Result> execute(List<Request> requests) {
        return CaseEscalationService.escalateCases(requests);
    }
}
