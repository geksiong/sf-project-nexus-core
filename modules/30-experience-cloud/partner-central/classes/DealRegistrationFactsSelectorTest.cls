@IsTest
private class DealRegistrationFactsSelectorTest {
    @IsTest
    static void emptyInputsShortCircuitWithoutQuerying() {
        DealRegistrationFactsSelector facts = DealRegistrationFactsSelector.newInstance();
        Assert.isTrue(facts.selectPartnerAccountIds(null).isEmpty());
        Assert.isTrue(facts.selectChannelManagerIds(new Set<Id>()).isEmpty());
        Assert.isTrue(facts.selectOpenRegistrationPartners(null, null).isEmpty());
        Assert.isTrue(facts.selectAccountIdsByName(new Set<String>()).isEmpty());
        Assert.areEqual(0, Limits.getQueries(), 'Empty inputs must not consume SOQL queries');
    }

    @IsTest
    static void accountNamesMatchCaseInsensitively() {
        insert new Account(Name = 'Initech Corp');
        Map<String, Id> ids = new DealRegistrationFactsSelector()
            .selectAccountIdsByName(new Set<String>{ DealRegistrationService.companyKey('  INITECH   corp ') });
        Assert.isTrue(ids.containsKey('initech corp'), String.valueOf(ids));
    }
}
