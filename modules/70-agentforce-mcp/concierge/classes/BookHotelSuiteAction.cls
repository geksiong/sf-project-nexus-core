/**
 * @description Headless action: books a hotel suite for the running user. Exposed to Agentforce (Hotel Concierge
 * topic) and as the `bookHotelSuite` MCP tool. The insert runs in user mode; Suite_Booking__c trigger rules price
 * the stay and reject double bookings. `global` because hosted MCP tools require global invocable actions.
 */
global with sharing class BookHotelSuiteAction {
    global class Request {
        @InvocableVariable(required=true label='Suite Id' description='Suite Id from Search Hotel Suites.')
        global String suiteId;
        @InvocableVariable(required=true label='Check-In Date' description='Arrival date (today or later).')
        global Date checkInDate;
        @InvocableVariable(required=true label='Nights' description='Length of stay in nights, 1 to 30.')
        global Integer nights;
        @InvocableVariable(label='Guests' description='Number of guests. Defaults to 1.')
        global Integer guests;
        @InvocableVariable(label='Guest Name' description='Name for the reservation. Defaults to the user.')
        global String guestName;
    }
    global class Result {
        @InvocableVariable(label='Is Success')
        global Boolean isSuccess;
        @InvocableVariable(label='Error Code')
        global String errorCode;
        @InvocableVariable(label='Error Message')
        global String errorMessage;
        @InvocableVariable(label='Payload')
        global HotelBookingConfirmation payload;
    }
    @InvocableMethod(
        label='Book Hotel Suite'
        description='Reserves an available hotel suite for the given check-in date and nights and returns the confirmation code.'
        category='Hospitality'
    )
    global static List<Result> execute(List<Request> requests) {
        return HotelConciergeService.bookSuites(requests);
    }
}
