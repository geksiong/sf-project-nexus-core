/**
 * @description One bookable suite in a concierge search result. Top-level `global` with JSON access and
 * @AuraEnabled fields: Custom Lightning Types reference it (`@apexClassType/c__HotelSuiteOffer`) and the HXL
 * `hotelCard` widget renders it in Agentforce and MCP clients.
 */
@JsonAccess(serializable='always' deserializable='always')
global class HotelSuiteOffer {
    @AuraEnabled
    @InvocableVariable(label='Suite Id' description='Record Id to pass to Book Hotel Suite.')
    global String suiteId;
    @AuraEnabled
    @InvocableVariable(label='Suite Name')
    global String suiteName;
    @AuraEnabled
    @InvocableVariable(label='Hotel Name')
    global String hotelName;
    @AuraEnabled
    @InvocableVariable(label='City')
    global String city;
    @AuraEnabled
    @InvocableVariable(label='Room Tier' description='Deluxe, Executive or Presidential.')
    global String roomTier;
    @AuraEnabled
    @InvocableVariable(label='Nightly Rate')
    global Decimal nightlyRate;
    @AuraEnabled
    @InvocableVariable(label='Total Price' description='Nightly rate times the requested nights.')
    global Decimal totalPrice;
    @AuraEnabled
    @InvocableVariable(label='Max Guests')
    global Integer maxGuests;
}
