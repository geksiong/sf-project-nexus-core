/**
 * @description Client for the ERP ledger API behind the Mock_ERP_Ledger named credential.
 *
 * POST callout:Mock_ERP_Ledger/ledger-entries
 *   request:  {"entries": [{"idempotencyKey", "capexRequestId", "amount", "department"}]}
 *   response: {"results": [{"idempotencyKey", "reference"} | {"idempotencyKey", "error"}]}
 * The idempotency key lets the ERP ignore a repeated post of the same entry.
 *
 * The mock endpoint does not exist in demo orgs, so ERP_Ledger_Setting__mdt.Default.Simulate__c (on by
 * default) returns synthetic references without a callout. Tests turn simulation off and use HttpCalloutMock.
 */
public virtual with sharing class ErpLedgerClient {
    public static final String ENDPOINT = 'callout:Mock_ERP_Ledger/ledger-entries';
    private static final Integer TIMEOUT_MS = 20000;

    @TestVisible
    private static ErpLedgerClient instance;
    @TestVisible
    private static Boolean simulateOverride;

    /** @description Returns the client; tests replace it with a TestStub mock via `instance`. */
    public static ErpLedgerClient newInstance() {
        if (instance == null) {
            instance = new ErpLedgerClient();
        }
        return instance;
    }

    public class PostResult {
        public Boolean success;
        public String reference;
        public String error;

        public PostResult(Boolean success, String reference, String error) {
            this.success = success;
            this.reference = reference;
            this.error = error;
        }
    }

    public static Boolean isSimulated() {
        if (simulateOverride != null) {
            return simulateOverride;
        }
        ERP_Ledger_Setting__mdt setting = ERP_Ledger_Setting__mdt.getInstance('Default');
        return setting != null && setting.Simulate__c;
    }

    /** @description Posts entries in one request. Every entry gets a result, keyed by idempotency key. */
    public virtual Map<String, PostResult> post(List<Ledger_Entry__c> entries) {
        if (isSimulated()) {
            Map<String, PostResult> simulated = new Map<String, PostResult>();
            for (Ledger_Entry__c entry : entries) {
                simulated.put(entry.Idempotency_Key__c, new PostResult(true, 'SIM-' + entry.Idempotency_Key__c, null));
            }
            return simulated;
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod('POST');
        request.setTimeout(TIMEOUT_MS);
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(new Map<String, Object>{ 'entries' => toPayload(entries) }));
        try {
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() < 200 || response.getStatusCode() > 299) {
                return failAll(
                    entries,
                    'ERP HTTP ' + response.getStatusCode() + ': ' + String.valueOf(response.getBody()).abbreviate(200)
                );
            }
            return parse(entries, response.getBody());
        } catch (CalloutException ex) {
            return failAll(entries, 'ERP callout failed: ' + ex.getMessage());
        }
    }

    private static List<Map<String, Object>> toPayload(List<Ledger_Entry__c> entries) {
        List<Map<String, Object>> payload = new List<Map<String, Object>>();
        for (Ledger_Entry__c entry : entries) {
            payload.add(
                new Map<String, Object>{
                    'idempotencyKey' => entry.Idempotency_Key__c,
                    'capexRequestId' => entry.CapEx_Request__c,
                    'amount' => entry.Amount__c,
                    'department' => entry.Department__c
                }
            );
        }
        return payload;
    }

    private static Map<String, PostResult> parse(List<Ledger_Entry__c> entries, String body) {
        Map<String, PostResult> byKey = new Map<String, PostResult>();
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            for (Object item : (List<Object>) parsed.get('results')) {
                Map<String, Object> result = (Map<String, Object>) item;
                String key = (String) result.get('idempotencyKey');
                String reference = (String) result.get('reference');
                byKey.put(
                    key,
                    String.isNotBlank(reference)
                        ? new PostResult(true, reference, null)
                        : new PostResult(false, null, 'ERP rejected the entry: ' + result.get('error'))
                );
            }
        } catch (Exception ex) {
            return failAll(entries, 'Invalid ERP response: ' + ex.getMessage());
        }
        for (Ledger_Entry__c entry : entries) {
            if (!byKey.containsKey(entry.Idempotency_Key__c)) {
                byKey.put(
                    entry.Idempotency_Key__c,
                    new PostResult(false, null, 'ERP returned no result for the entry.')
                );
            }
        }
        return byKey;
    }

    private static Map<String, PostResult> failAll(List<Ledger_Entry__c> entries, String error) {
        Map<String, PostResult> failed = new Map<String, PostResult>();
        for (Ledger_Entry__c entry : entries) {
            failed.put(entry.Idempotency_Key__c, new PostResult(false, null, error));
        }
        return failed;
    }
}
