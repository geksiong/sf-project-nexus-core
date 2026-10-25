/**
 * @description Headless action that re-queues a failed ERP ledger posting, or recovers an approval stuck
 * as Pending with no ledger entry. Reusable by Flow, Agentforce
 * and MCP via the uniform result envelope.
 */
public with sharing class RetryLedgerPostingAction {
    public class Request {
        @InvocableVariable(required=true label='CapEx Request Id')
        public Id capexRequestId;
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
        public Id capexRequestId;
        @InvocableVariable
        public String ledgerStatus;
    }
    @InvocableMethod(
        label='Retry Ledger Posting'
        description='Re-queues a failed ERP ledger posting, or recovers an approved CapEx request stuck as Pending.'
        category='Operations'
    )
    public static List<Result> execute(List<Request> requests) {
        return LedgerPostingService.retryPostings(requests);
    }
}
