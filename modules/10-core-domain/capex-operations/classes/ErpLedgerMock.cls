/**
 * @description HttpCalloutMock for the ERP ledger API: echoes a reference for every entry, rejects listed
 * keys, or fails the whole request with an HTTP status.
 */
@IsTest
public class ErpLedgerMock implements HttpCalloutMock {
    public Integer statusCode = 201;
    public Set<String> rejectedKeys = new Set<String>();
    public String rawBody;
    public Integer calls = 0;
    public List<String> requestBodies = new List<String>();

    public static ErpLedgerMock install() {
        ErpLedgerClient.simulateOverride = false;
        ErpLedgerMock mock = new ErpLedgerMock();
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    public HttpResponse respond(HttpRequest request) {
        calls++;
        requestBodies.add(request.getBody());
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        if (rawBody != null) {
            response.setBody(rawBody);
            return response;
        }
        if (statusCode >= 300) {
            response.setBody('{"error":"ERP unavailable"}');
            return response;
        }
        List<Object> results = new List<Object>();
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
        for (Object item : (List<Object>) body.get('entries')) {
            String key = (String) ((Map<String, Object>) item).get('idempotencyKey');
            results.add(
                rejectedKeys.contains(key)
                    ? new Map<String, Object>{ 'idempotencyKey' => key, 'error' => 'Cost centre closed' }
                    : new Map<String, Object>{ 'idempotencyKey' => key, 'reference' => 'ERP-' + key.right(6) }
            );
        }
        response.setBody(JSON.serialize(new Map<String, Object>{ 'results' => results }));
        return response;
    }
}
