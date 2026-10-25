@IsTest
private class ErpLedgerClientTest {
    private static List<Ledger_Entry__c> entries(Integer count) {
        List<Ledger_Entry__c> result = new List<Ledger_Entry__c>();
        for (Integer i = 0; i < count; i++) {
            Id requestId = TestDataFactory.getFakeId(CapEx_Request__c.SObjectType);
            result.add(
                new Ledger_Entry__c(
                    CapEx_Request__c = requestId,
                    Idempotency_Key__c = requestId,
                    Amount__c = 100 + i,
                    Department__c = 'Field Operations'
                )
            );
        }
        return result;
    }

    @IsTest
    static void simulationReturnsReferencesWithoutACallout() {
        ErpLedgerClient.simulateOverride = true;
        List<Ledger_Entry__c> batch = entries(2);

        Map<String, ErpLedgerClient.PostResult> results = ErpLedgerClient.newInstance().post(batch);

        Assert.isTrue(results.get(batch[0].Idempotency_Key__c).success);
        Assert.areEqual('SIM-' + batch[0].Idempotency_Key__c, results.get(batch[0].Idempotency_Key__c).reference);
        Assert.areEqual(0, Limits.getCallouts());
    }

    @IsTest
    static void postsOneRequestAndMapsEachResult() {
        ErpLedgerMock mock = ErpLedgerMock.install();
        List<Ledger_Entry__c> batch = entries(3);
        mock.rejectedKeys.add(batch[1].Idempotency_Key__c);

        Map<String, ErpLedgerClient.PostResult> results = ErpLedgerClient.newInstance().post(batch);

        Assert.areEqual(1, mock.calls, 'One request per batch');
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.requestBodies[0]);
        Map<String, Object> first = (Map<String, Object>) ((List<Object>) sent.get('entries'))[0];
        Assert.areEqual(batch[0].Idempotency_Key__c, first.get('idempotencyKey'), 'Idempotency key is sent');
        Assert.areEqual(100, first.get('amount'));
        Assert.isTrue(results.get(batch[0].Idempotency_Key__c).success);
        Assert.isFalse(results.get(batch[1].Idempotency_Key__c).success);
        Assert.isTrue(results.get(batch[1].Idempotency_Key__c).error.contains('Cost centre closed'));
    }

    @IsTest
    static void httpErrorsAndBadResponsesFailEveryEntry() {
        ErpLedgerMock mock = ErpLedgerMock.install();
        List<Ledger_Entry__c> batch = entries(2);

        mock.statusCode = 503;
        Map<String, ErpLedgerClient.PostResult> unavailable = ErpLedgerClient.newInstance().post(batch);
        Assert.isFalse(unavailable.get(batch[1].Idempotency_Key__c).success);
        Assert.isTrue(unavailable.get(batch[1].Idempotency_Key__c).error.startsWith('ERP HTTP 503'));

        mock.statusCode = 200;
        mock.rawBody = 'not json';
        Assert.isTrue(
            ErpLedgerClient.newInstance()
                .post(batch)
                .get(batch[0].Idempotency_Key__c)
                .error.startsWith('Invalid ERP response')
        );

        mock.rawBody = '{"results":[]}';
        Assert.areEqual(
            'ERP returned no result for the entry.',
            ErpLedgerClient.newInstance().post(batch).get(batch[0].Idempotency_Key__c).error
        );
    }

    @IsTest
    static void defaultSettingSimulatesTheErp() {
        Assert.isTrue(ErpLedgerClient.isSimulated(), 'ERP_Ledger_Setting.Default ships with Simulate__c on');
    }
}
