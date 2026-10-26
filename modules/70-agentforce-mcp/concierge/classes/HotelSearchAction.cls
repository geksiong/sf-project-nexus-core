/**
 * @description Headless action: available hotel suites for a city and stay. Exposed to Agentforce (Hotel
 * Concierge topic) and as the `searchHotels` MCP tool, whose result renders as the HXL `hotelCard` widget.
 * `global` because hosted MCP tools require global invocable actions.
 */
global with sharing class HotelSearchAction {
    global class Request {
        @InvocableVariable(required=true label='City' description='City to stay in, for example Singapore.')
        global String city;
        @InvocableVariable(required=true label='Check-In Date' description='Arrival date (today or later).')
        global Date checkInDate;
        @InvocableVariable(label='Nights' description='Length of stay in nights, 1 to 30. Defaults to 1.')
        global Integer nights;
        @InvocableVariable(label='Guests' description='Number of guests. Defaults to 1.')
        global Integer guests;
    }
    global class Result {
        @InvocableVariable(label='Is Success')
        global Boolean isSuccess;
        @InvocableVariable(label='Error Code')
        global String errorCode;
        @InvocableVariable(label='Error Message')
        global String errorMessage;
        @InvocableVariable(label='Payload')
        global HotelSearchPayload payload;
    }
    @InvocableMethod(
        label='Search Hotel Suites'
        description='Finds available hotel suites in a city for a check-in date and number of nights, cheapest first.'
        category='Hospitality'
    )
    global static List<Result> execute(List<Request> requests) {
        return HotelConciergeService.searchSuites(requests);
    }
}
