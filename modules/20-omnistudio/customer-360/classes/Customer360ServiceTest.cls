/**
 * @description Unit tests for the VIP_Customer360 remote action: health rules, Data Mapper output shapes
 * (single object vs list, string-typed values) and the OmniStudio Callable contract.
 */
@IsTest
private class Customer360ServiceTest {
    private static Map<String, Object> opp(Decimal amount, String discountStatus) {
        return new Map<String, Object>{ 'Amount' => amount, 'Discount_Approval_Status__c' => discountStatus };
    }

    private static Map<String, Object> caseRecord(String status, String priority, Object slaViolatedOn) {
        return new Map<String, Object>{
            'Status' => status,
            'Priority' => priority,
            'SLA_Violated_On__c' => slaViolatedOn
        };
    }

    private static Map<String, Object> call(Map<String, Object> input) {
        Map<String, Object> output = new Map<String, Object>();
        new Customer360Service()
            .call(
                Customer360Service.ACTION_SUMMARIZE,
                new Map<String, Object>{ 'input' => input, 'output' => output, 'options' => new Map<String, Object>() }
            );
        return output;
    }

    @IsTest
    static void healthyAccountWithPipeline() {
        Map<String, Object> output = call(
            new Map<String, Object>{
                'Account' => new Map<String, Object>{ 'Name' => 'Acme', 'Credit_Hold__c' => false },
                'Opportunities' => new List<Object>{
                    opp(1000, 'Not Required'),
                    opp(2500.50, 'Approved'),
                    new Map<String, Object>{ 'Amount' => 99999, 'IsClosed' => true }
                },
                'Cases' => new List<Object>{ caseRecord('Working', 'Low', null) }
            }
        );

        Assert.areEqual(Customer360Service.HEALTH_HEALTHY, output.get('health'));
        Assert.areEqual('success', output.get('healthVariant'));
        Assert.areEqual('No open risks', output.get('healthReasons'));
        Assert.areEqual(3500.50, output.get('openPipelineAmount'));
        Assert.areEqual(2, output.get('openOpportunities'), 'Closed records are ignored');
        Assert.areEqual(1, output.get('openCases'));
    }

    @IsTest
    static void creditHoldEscalationsAndSlaViolationsPutTheAccountAtRisk() {
        Map<String, Object> output = call(
            new Map<String, Object>{
                'Account' => new Map<String, Object>{ 'Credit_Hold__c' => 'true' },
                'Cases' => new List<Object>{
                    caseRecord('Escalated', 'High', '2026-10-25T10:00:00.000Z'),
                    caseRecord('New', 'Medium', null)
                }
            }
        );

        Assert.areEqual(Customer360Service.HEALTH_AT_RISK, output.get('health'));
        Assert.areEqual('error', output.get('healthVariant'));
        Assert.isTrue(output.get('creditHold') == true, 'String "true" from the Data Mapper is a credit hold');
        Assert.areEqual(1, output.get('escalatedCases'));
        Assert.areEqual(1, output.get('slaViolations'));
        String reasons = (String) output.get('healthReasons');
        Assert.isTrue(reasons.startsWith('Account is on credit hold; 1 escalated case(s)'), reasons);
        Assert.isTrue(reasons.contains('1 high-priority case(s)'), reasons);
    }

    @IsTest
    static void highPriorityCasesAndPendingDiscountsNeedWatching() {
        Map<String, Object> output = call(
            new Map<String, Object>{
                'Account' => new Map<String, Object>{ 'Credit_Hold__c' => false },
                'Opportunities' => opp(9000, 'Pending'),
                'Cases' => caseRecord('Working', 'High', null)
            }
        );

        Assert.areEqual(Customer360Service.HEALTH_WATCH, output.get('health'), 'Single records arrive as objects');
        Assert.areEqual('warning', output.get('healthVariant'));
        Assert.areEqual(1, output.get('pendingDiscountApprovals'));
        Assert.areEqual(1, output.get('highPriorityCases'));
        Assert.areEqual(9000, output.get('openPipelineAmount'));
    }

    @IsTest
    static void noRelatedRecordsIsHealthy() {
        Map<String, Object> output = call(
            new Map<String, Object>{
                'Account' => new Map<String, Object>{ 'Name' => 'New Co', 'Credit_Hold__c' => false }
            }
        );

        Assert.areEqual(Customer360Service.HEALTH_HEALTHY, output.get('health'));
        Assert.areEqual(true, output.get('complete'));
        Assert.areEqual(0, output.get('openCases'));
        Assert.areEqual(0, output.get('openPipelineAmount'));
    }

    /** @description Data the viewer cannot see (omitted by the FLS-enforcing Data Mapper) is never "Healthy". */
    @IsTest
    static void invisibleCreditStatusIsIncompleteNotHealthy() {
        Map<String, Object> hidden = call(
            new Map<String, Object>{ 'Account' => new Map<String, Object>{ 'Name' => 'Globex' } }
        );
        Assert.areEqual(Customer360Service.HEALTH_INCOMPLETE, hidden.get('health'));
        Assert.areEqual('warning', hidden.get('healthVariant'));
        Assert.areEqual(false, hidden.get('complete'));
        Assert.areEqual('Credit status not visible to you', hidden.get('healthReasons'));

        Map<String, Object> noAccount = call(new Map<String, Object>());
        Assert.areEqual(Customer360Service.HEALTH_INCOMPLETE, noAccount.get('health'));
        Assert.areEqual('Account not visible to you', noAccount.get('healthReasons'));

        Map<String, Object> hiddenButWatch = call(
            new Map<String, Object>{
                'Account' => new Map<String, Object>{ 'Name' => 'Globex' },
                'Cases' => caseRecord('New', 'High', null)
            }
        );
        Assert.areEqual(
            Customer360Service.HEALTH_WATCH,
            hiddenButWatch.get('health'),
            'A real watch item still decides'
        );
        Assert.isTrue(((String) hiddenButWatch.get('healthReasons')).contains('Credit status not visible'));

        Map<String, Object> hiddenButRisk = call(
            new Map<String, Object>{
                'Account' => new Map<String, Object>(),
                'Cases' => caseRecord('Escalated', 'Low', null)
            }
        );
        Assert.areEqual(Customer360Service.HEALTH_AT_RISK, hiddenButRisk.get('health'));
    }

    @IsTest
    static void unknownActionsAndBadDataAreReportedAndLoggedNotThrown() {
        Map<String, Object> output = new Map<String, Object>();
        new Customer360Service()
            .call('explode', new Map<String, Object>{ 'input' => new Map<String, Object>(), 'output' => output });
        Assert.areEqual(Customer360Service.HEALTH_UNAVAILABLE, output.get('health'));
        Assert.isTrue(((String) output.get('error')).contains('Unknown action'));

        Map<String, Object> badAmount = call(
            new Map<String, Object>{
                'Opportunities' => new List<Object>{ new Map<String, Object>{ 'Amount' => 'n/a' } }
            }
        );
        Assert.areEqual(Customer360Service.HEALTH_UNAVAILABLE, badAmount.get('health'));

        Object direct = new Customer360Service().call(Customer360Service.ACTION_SUMMARIZE, null);
        Assert.areEqual(
            Customer360Service.HEALTH_INCOMPLETE,
            ((Map<String, Object>) direct).get('health'),
            'Input map optional; no account data is incomplete'
        );
    }
}
