/**
 * @description OmniStudio remote action for the VIP_Customer360 Integration Procedure (Demo App 4).
 *
 * The Integration Procedure reads the account, its open opportunities and its open cases through the
 * DMCustomer360Extract Data Mapper (field-level security enforced, no SOQL here) and sends that output to
 * `summarize`, which derives the Customer 360 health indicators shown by the FC_CustomerHeader FlexCard.
 *
 * Contract (OmniStudio System.Callable): `call(action, {input, output, options})`; results are written to
 * `output`. Failures are logged with Nebula Logger and returned as `error` instead of being thrown, so the
 * FlexCard degrades to "Unavailable" rather than failing.
 *
 * The Data Mapper omits fields and records the viewer cannot see. Missing data is never presented as good
 * health: when the account or its credit status is not visible, the result is "Incomplete" unless a risk or
 * watch item already decides it, and `complete` is false.
 */
public with sharing class Customer360Service implements System.Callable {
    public static final String ACTION_SUMMARIZE = 'summarize';
    public static final String HEALTH_AT_RISK = 'At Risk';
    public static final String HEALTH_WATCH = 'Watch';
    public static final String HEALTH_HEALTHY = 'Healthy';
    public static final String HEALTH_INCOMPLETE = 'Incomplete';
    public static final String HEALTH_UNAVAILABLE = 'Unavailable';

    private static final String DISCOUNT_PENDING = 'Pending';
    private static final String PRIORITY_HIGH = 'High';
    private static final String STATUS_ESCALATED = 'Escalated';

    public Object call(String action, Map<String, Object> args) {
        args = args ?? new Map<String, Object>();
        Map<String, Object> input = (Map<String, Object>) (args.get('input') ?? args);
        Map<String, Object> output = (Map<String, Object>) (args.get('output') ?? new Map<String, Object>());
        try {
            switch on action {
                when 'summarize' {
                    output.putAll(summarize(input));
                }
                when else {
                    throw new IllegalArgumentException('Unknown action: ' + action);
                }
            }
        } catch (Exception ex) {
            Logger.error('Customer360Service.' + action + ' failed: ' + ex.getMessage(), ex);
            Logger.saveLog();
            output.put('health', HEALTH_UNAVAILABLE);
            output.put('error', ex.getMessage());
        }
        return output;
    }

    /** @description Health indicators from the Data Mapper output (Account, Opportunities, Cases). */
    @TestVisible
    private static Map<String, Object> summarize(Map<String, Object> input) {
        Map<String, Object> account = input.get('Account') instanceof Map<String, Object>
            ? (Map<String, Object>) input.get('Account')
            : new Map<String, Object>();
        List<Map<String, Object>> opportunities = openRecords(input.get('Opportunities'));
        List<Map<String, Object>> cases = openRecords(input.get('Cases'));

        Decimal openPipeline = 0;
        Integer pendingDiscounts = 0;
        for (Map<String, Object> opp : opportunities) {
            openPipeline += toDecimal(opp.get('Amount'));
            if (opp.get('Discount_Approval_Status__c') == DISCOUNT_PENDING) {
                pendingDiscounts++;
            }
        }
        Integer highPriority = 0;
        Integer escalated = 0;
        Integer slaViolations = 0;
        for (Map<String, Object> c : cases) {
            if (c.get('Priority') == PRIORITY_HIGH) {
                highPriority++;
            }
            if (c.get('Status') == STATUS_ESCALATED) {
                escalated++;
            }
            if (c.get('SLA_Violated_On__c') != null) {
                slaViolations++;
            }
        }
        Boolean creditHold = toBoolean(account.get('Credit_Hold__c'));
        // Credit_Hold__c is a checkbox (never null), so a missing key means the viewer cannot see it.
        Boolean creditKnown = account.containsKey('Credit_Hold__c');

        List<String> riskReasons = new List<String>();
        if (creditHold) {
            riskReasons.add('Account is on credit hold');
        }
        if (escalated > 0) {
            riskReasons.add(escalated + ' escalated case(s)');
        }
        if (slaViolations > 0) {
            riskReasons.add(slaViolations + ' case(s) with an SLA violation');
        }
        List<String> watchReasons = new List<String>();
        if (highPriority > 0) {
            watchReasons.add(highPriority + ' high-priority case(s)');
        }
        if (pendingDiscounts > 0) {
            watchReasons.add(pendingDiscounts + ' discount approval(s) pending');
        }
        if (!creditKnown) {
            watchReasons.add(account.isEmpty() ? 'Account not visible to you' : 'Credit status not visible to you');
        }
        String health = !riskReasons.isEmpty()
            ? HEALTH_AT_RISK
            : watchReasons.size() > (creditKnown ? 0 : 1)
                  ? HEALTH_WATCH
                  : !creditKnown ? HEALTH_INCOMPLETE : HEALTH_HEALTHY;
        List<String> reasons = new List<String>(riskReasons);
        reasons.addAll(watchReasons);

        return new Map<String, Object>{
            'health' => health,
            'healthVariant' => health == HEALTH_AT_RISK ? 'error' : health == HEALTH_HEALTHY ? 'success' : 'warning',
            'complete' => creditKnown,
            'healthReasons' => reasons.isEmpty() ? 'No open risks' : String.join(reasons, '; '),
            'creditHold' => creditHold,
            'openOpportunities' => opportunities.size(),
            'openPipelineAmount' => openPipeline,
            'pendingDiscountApprovals' => pendingDiscounts,
            'openCases' => cases.size(),
            'highPriorityCases' => highPriority,
            'escalatedCases' => escalated,
            'slaViolations' => slaViolations
        };
    }

    /**
     * @description Open records from a Data Mapper list. Data Mappers return a single object instead of a list
     * when exactly one record matches. The Data Mapper already filters IsClosed = false; closed records are
     * skipped here too, so the indicators stay correct even if that filter is changed.
     */
    private static List<Map<String, Object>> openRecords(Object value) {
        List<Object> items = value instanceof List<Object> ? (List<Object>) value : new List<Object>{ value };
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Object item : items) {
            if (item instanceof Map<String, Object> && !toBoolean(((Map<String, Object>) item).get('IsClosed'))) {
                result.add((Map<String, Object>) item);
            }
        }
        return result;
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return 0;
        }
        return value instanceof Decimal ? (Decimal) value : Decimal.valueOf(String.valueOf(value));
    }

    private static Boolean toBoolean(Object value) {
        return value == true || String.valueOf(value) == 'true';
    }
}
