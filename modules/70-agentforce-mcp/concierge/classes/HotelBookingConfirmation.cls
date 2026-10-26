/**
 * @description Payload of BookHotelSuiteAction: the confirmed reservation. Top-level `global` so agents and MCP
 * clients receive a typed object.
 */
@JsonAccess(serializable='always' deserializable='always')
global class HotelBookingConfirmation {
    @AuraEnabled
    @InvocableVariable(label='Booking Id')
    global String bookingId;
    @AuraEnabled
    @InvocableVariable(label='Confirmation Code')
    global String confirmationCode;
    @AuraEnabled
    @InvocableVariable(label='Suite Name')
    global String suiteName;
    @AuraEnabled
    @InvocableVariable(label='Hotel Name')
    global String hotelName;
    @AuraEnabled
    @InvocableVariable(label='Check-In Date')
    global Date checkInDate;
    @AuraEnabled
    @InvocableVariable(label='Check-Out Date')
    global Date checkOutDate;
    @AuraEnabled
    @InvocableVariable(label='Total Price')
    global Decimal totalPrice;
    @AuraEnabled
    @InvocableVariable(label='Currency Code' description='ISO currency of the total price.')
    global String currencyCode;
}
