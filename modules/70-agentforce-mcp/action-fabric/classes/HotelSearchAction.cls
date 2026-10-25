public with sharing class HotelSearchAction {
    public class Request {
        @InvocableVariable(required=true label='City Location')
        public String city;
        @InvocableVariable(required=true label='Check-In Date')
        public Date checkInDate;
    }
    public class Response {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        @InvocableVariable(label='Hotel Payload')
        public HotelDetailsPayload hotelDetails;
    }
    public class HotelDetailsPayload {
        @InvocableVariable public String hotelName;
        @InvocableVariable public Decimal nightlyRate;
        @InvocableVariable public String roomTier;
        @InvocableVariable public String confirmationId;
    }
    @InvocableMethod(label='Search Available Hotels' category='Hospitality')
    public static List<Response> searchHotels(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.isSuccess = true;
            HotelDetailsPayload payload = new HotelDetailsPayload();
            payload.hotelName = 'Grand Palace ' + req.city;
            payload.nightlyRate = 350.00;
            payload.roomTier = 'Executive Luxury Suite';
            payload.confirmationId = 'CONF-99214';
            res.hotelDetails = payload;
            responses.add(res);
        }
        return responses;
    }
}