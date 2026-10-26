/**
 * @description Payload of HotelSearchAction: the stay that was searched and the available suites, cheapest first.
 * Top-level `global` for the Custom Lightning Types (`hotelSearchResponse`, `hotelSearchOutputValues`).
 */
@JsonAccess(serializable='always' deserializable='always')
global class HotelSearchPayload {
    @AuraEnabled
    @InvocableVariable(label='City')
    global String city;
    @AuraEnabled
    @InvocableVariable(label='Check-In Date')
    global Date checkInDate;
    @AuraEnabled
    @InvocableVariable(label='Check-Out Date')
    global Date checkOutDate;
    @AuraEnabled
    @InvocableVariable(label='Nights')
    global Integer nights;
    @AuraEnabled
    @InvocableVariable(label='Currency Code' description='ISO currency of the rates and totals.')
    global String currencyCode;
    @AuraEnabled
    @InvocableVariable(label='Suite Count' description='Number of available suites returned.')
    global Integer suiteCount;
    @AuraEnabled
    @InvocableVariable(label='Suites' description='Available suites, cheapest first.')
    global List<HotelSuiteOffer> suites;
}
