/**
 * @description In-memory unit tests for deal registration routing, the channel conflict rule and input
 * validation (facts selector stubbed; no SOQL or DML).
 */
@IsTest
private class DealRegistrationServiceTest {
    private static final Id PARTNER_A = TestDataFactory.getFakeId(Account.SObjectType);
    private static final Id PARTNER_B = TestDataFactory.getFakeId(Account.SObjectType);
    private static final Id MANAGER = TestDataFactory.getFakeId(User.SObjectType);

    private static TestStub facts;

    private static void mockFacts(Map<Id, Id> partnerOfUser, Map<String, Id> openRegistrations) {
        facts = new TestStub()
            .returns('selectPartnerAccountIds', partnerOfUser)
            .returns('selectChannelManagerIds', new Map<Id, Id>{ PARTNER_A => MANAGER, PARTNER_B => MANAGER })
            .returns('selectOpenRegistrationPartners', openRegistrations);
        DealRegistrationFactsSelector.instance = (DealRegistrationFactsSelector) facts.create(
            DealRegistrationFactsSelector.class
        );
    }

    private static Deal_Registration__c reg(String company) {
        return new Deal_Registration__c(
            Customer_Company__c = company,
            Estimated_Amount__c = 1000,
            Expected_Close_Date__c = Date.today().addDays(30),
            Status__c = 'Approved'
        );
    }

    private static String errors(SObject record) {
        List<String> messages = new List<String>();
        for (Database.Error err : record.getErrors()) {
            messages.add(err.getMessage());
        }
        return String.join(messages, ' | ');
    }

    @IsTest
    static void routesToThePartnersChannelManager() {
        mockFacts(new Map<Id, Id>{ UserInfo.getUserId() => PARTNER_A }, new Map<String, Id>());
        Deal_Registration__c registration = reg('  Initech   Corp ');

        DealRegistrationService.prepareRegistrations(new List<Deal_Registration__c>{ registration });

        Assert.isFalse(registration.hasErrors(), errors(registration));
        Assert.areEqual(PARTNER_A, registration.Partner_Account__c);
        Assert.areEqual(MANAGER, registration.Channel_Manager__c);
        Assert.areEqual(DealRegistrationService.STATUS_SUBMITTED, registration.Status__c, 'Always starts Submitted');
        Assert.areEqual('Initech Corp', registration.Customer_Company__c, 'Whitespace normalised');
    }

    @IsTest
    static void channelConflictsNameNeitherPartnerNorRegistration() {
        mockFacts(
            new Map<Id, Id>{ UserInfo.getUserId() => PARTNER_A },
            new Map<String, Id>{ 'initech corp' => PARTNER_B, 'globex' => PARTNER_A }
        );
        Deal_Registration__c otherPartner = reg('INITECH CORP');
        Deal_Registration__c samePartner = reg('Globex');

        DealRegistrationService.prepareRegistrations(new List<Deal_Registration__c>{ otherPartner, samePartner });

        Assert.areEqual(
            DealRegistrationService.CONFLICT_PREFIX + 'INITECH CORP is already registered by another partner.',
            errors(otherPartner)
        );
        Assert.isTrue(
            errors(samePartner).contains('your organisation already has an open registration'),
            errors(samePartner)
        );
    }

    @IsTest
    static void duplicatesInOneBatchConflictWithEachOther() {
        mockFacts(new Map<Id, Id>{ UserInfo.getUserId() => PARTNER_A }, new Map<String, Id>());
        Deal_Registration__c first = reg('Umbrella');
        Deal_Registration__c second = reg('umbrella ');

        DealRegistrationService.prepareRegistrations(new List<Deal_Registration__c>{ first, second });

        Assert.isFalse(first.hasErrors(), errors(first));
        Assert.isTrue(errors(second).startsWith(DealRegistrationService.CONFLICT_PREFIX), errors(second));
    }

    @IsTest
    static void nonPartnersAndUnmanagedPartnersAreRejected() {
        mockFacts(new Map<Id, Id>(), new Map<String, Id>());
        Deal_Registration__c noPartner = reg('Hooli');
        DealRegistrationService.prepareRegistrations(new List<Deal_Registration__c>{ noPartner });
        Assert.isTrue(errors(noPartner).contains('must come from a partner user'), errors(noPartner));

        facts.returns('selectChannelManagerIds', new Map<Id, Id>());
        Deal_Registration__c unmanaged = reg('Hooli');
        unmanaged.Partner_Account__c = PARTNER_A;
        DealRegistrationService.prepareRegistrations(new List<Deal_Registration__c>{ unmanaged });
        Assert.isTrue(errors(unmanaged).contains('no active channel manager'), errors(unmanaged));
    }

    @IsTest
    static void invalidRequestsFailBeforeAnyDml() {
        List<SubmitDealRegistrationAction.Request> requests = new List<SubmitDealRegistrationAction.Request>();
        for (Integer i = 0; i < 5; i++) {
            SubmitDealRegistrationAction.Request req = new SubmitDealRegistrationAction.Request();
            req.customerCompany = 'Acme';
            req.estimatedAmount = 100;
            req.expectedCloseDate = Date.today();
            requests.add(req);
        }
        requests[0].customerCompany = ' ';
        requests[1].estimatedAmount = 0;
        requests[2].expectedCloseDate = Date.today().addDays(-1);
        requests[3].productInterest = 'Time Machines';
        requests[4].customerEmail = 'pat at example dot com';

        List<SubmitDealRegistrationAction.Result> results = SubmitDealRegistrationAction.execute(requests);

        for (SubmitDealRegistrationAction.Result result : results) {
            Assert.isFalse(result.isSuccess);
            Assert.areEqual(DealRegistrationService.ERROR_INVALID_INPUT, result.errorCode, result.errorMessage);
        }
        Assert.areEqual(0, Limits.getDmlStatements());
        Assert.areEqual('initech corp', DealRegistrationService.companyKey('  Initech   CORP '));
    }
}
