/**
 * @description Nexus Hotel Concierge (Demo App 9): suite search and booking for Agentforce and MCP clients.
 *
 *  searchSuites      (HotelSearchAction)    active suites in the city the user can see (user mode), minus suites
 *                                           already booked for any of the nights and suites too small for the
 *                                           party, cheapest first, at most MAX_OFFERS.
 *  bookSuites        (BookHotelSuiteAction) user-mode insert of a Confirmed Suite_Booking__c; the trigger rules
 *                                           below decide availability and price.
 *  applyBookingRules (before insert/update) for every Confirmed booking that is new or changes its suite, dates,
 *                                           guests or status: the suite must be active and large enough, no other
 *                                           confirmed booking (anyone's, or another in the same save) may overlap,
 *                                           and Total_Price__c = nightly rate x nights. The suites are locked first
 *                                           (FOR UPDATE), so concurrent bookings of one suite cannot both pass.
 *
 * Bookings are private, but availability and pricing must not depend on who asks or saves (a guest, an agent, an
 * integration), so the rules read through HotelBookingFactsSelector (system mode).
 */
public with sharing class HotelConciergeService {
    public static final String STATUS_CONFIRMED = 'Confirmed';
    public static final Integer MAX_NIGHTS = 30;
    public static final Integer MAX_OFFERS = 5;
    public static final Integer MAX_ADVANCE_DAYS = 365;
    public static final String UNAVAILABLE_MESSAGE = 'The suite is already booked for some of these nights.';

    public static final String ERROR_INVALID_INPUT = 'INVALID_INPUT';
    public static final String ERROR_NOT_AVAILABLE = 'NOT_AVAILABLE';
    public static final String ERROR_DML = 'DML_ERROR';

    /** @description DML status codes that are expected rejections (rules, access), logged at WARN. */
    private static final Set<StatusCode> EXPECTED_REJECTION_CODES = new Set<StatusCode>{
        StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
        StatusCode.INSUFFICIENT_ACCESS_OR_READONLY,
        StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY,
        StatusCode.INVALID_CROSS_REFERENCE_KEY
    };

    // ---------------------------------------------------------------------------------------------
    // Search (HotelSearchAction)
    // ---------------------------------------------------------------------------------------------

    public static List<HotelSearchAction.Result> searchSuites(List<HotelSearchAction.Request> requests) {
        List<HotelSearchAction.Result> results = new List<HotelSearchAction.Result>();
        Set<String> cities = new Set<String>();
        Date windowStart;
        Date windowEnd;
        for (HotelSearchAction.Request req : requests) {
            HotelSearchAction.Result result = new HotelSearchAction.Result();
            results.add(result);
            String error = validateStay(req.checkInDate, nightsOrDefault(req.nights), req.guests);
            if (String.isBlank(req.city)) {
                error = 'A city is required.';
            }
            if (error != null) {
                result.isSuccess = false;
                result.errorCode = ERROR_INVALID_INPUT;
                result.errorMessage = error;
                Logger.warn('HotelSearchAction ' + ERROR_INVALID_INPUT + ': ' + error);
                continue;
            }
            cities.add(req.city.trim());
            Date checkOut = req.checkInDate.addDays(nightsOrDefault(req.nights));
            windowStart = windowStart == null || req.checkInDate < windowStart ? req.checkInDate : windowStart;
            windowEnd = windowEnd == null || checkOut > windowEnd ? checkOut : windowEnd;
        }

        List<Hotel_Suite__c> suites = HotelSuitesSelector.newInstance().selectActiveByCities(cities);
        Set<Id> suiteIds = new Map<Id, Hotel_Suite__c>(suites).keySet();
        Map<Id, List<Suite_Booking__c>> bookingsBySuite = groupBySuite(
            HotelBookingFactsSelector.newInstance().selectConfirmedBookings(suiteIds, windowStart, windowEnd, null)
        );

        for (Integer i = 0; i < requests.size(); i++) {
            if (results[i].isSuccess == false) {
                continue;
            }
            HotelSearchAction.Request req = requests[i];
            Integer nights = nightsOrDefault(req.nights);
            HotelSearchPayload payload = new HotelSearchPayload();
            payload.city = req.city.trim();
            payload.checkInDate = req.checkInDate;
            payload.checkOutDate = req.checkInDate.addDays(nights);
            payload.nights = nights;
            payload.currencyCode = UserInfo.getDefaultCurrency();
            payload.suites = new List<HotelSuiteOffer>();
            for (Hotel_Suite__c suite : suites) {
                if (payload.suites.size() == MAX_OFFERS) {
                    break;
                }
                Boolean sameCity = suite.City__c.equalsIgnoreCase(payload.city);
                Boolean fits = req.guests == null || suite.Max_Guests__c == null || req.guests <= suite.Max_Guests__c;
                if (
                    sameCity &&
                    fits &&
                    !overlaps(bookingsBySuite.get(suite.Id), payload.checkInDate, payload.checkOutDate)
                ) {
                    payload.suites.add(toOffer(suite, nights));
                }
            }
            payload.suiteCount = payload.suites.size();
            results[i].isSuccess = true;
            results[i].payload = payload;
        }
        if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
        return results;
    }

    // ---------------------------------------------------------------------------------------------
    // Booking (BookHotelSuiteAction)
    // ---------------------------------------------------------------------------------------------

    public static List<BookHotelSuiteAction.Result> bookSuites(List<BookHotelSuiteAction.Request> requests) {
        List<BookHotelSuiteAction.Result> results = new List<BookHotelSuiteAction.Result>();
        List<Suite_Booking__c> bookings = new List<Suite_Booking__c>();
        List<Integer> bookingIndexes = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            BookHotelSuiteAction.Request req = requests[i];
            results.add(new BookHotelSuiteAction.Result());
            String error = validateStay(req.checkInDate, req.nights, req.guests);
            Id suiteId = toSuiteId(req.suiteId);
            if (suiteId == null) {
                error = 'Suite Id does not reference a Hotel Suite.';
            }
            if (error != null) {
                fail(results[i], ERROR_INVALID_INPUT, error, null, true);
                continue;
            }
            bookings.add(
                new Suite_Booking__c(
                    Hotel_Suite__c = suiteId,
                    Check_In__c = req.checkInDate,
                    Check_Out__c = req.checkInDate.addDays(req.nights),
                    Guests__c = req.guests == null ? 1 : req.guests,
                    Guest_Name__c = String.isBlank(req.guestName)
                        ? UserInfo.getName()
                        : req.guestName.trim().abbreviate(120),
                    Status__c = STATUS_CONFIRMED
                )
            );
            bookingIndexes.add(i);
        }

        List<Database.SaveResult> saveResults = Database.insert(bookings, false, AccessLevel.USER_MODE);
        Set<Id> bookedIds = new Set<Id>();
        for (Database.SaveResult saveResult : saveResults) {
            if (saveResult.isSuccess()) {
                bookedIds.add(saveResult.getId());
            }
        }
        Map<Id, Suite_Booking__c> confirmed = new Map<Id, Suite_Booking__c>(
            SuiteBookingsSelector.newInstance().selectByIds(bookedIds)
        );
        for (Integer j = 0; j < saveResults.size(); j++) {
            BookHotelSuiteAction.Result result = results[bookingIndexes[j]];
            if (saveResults[j].isSuccess()) {
                result.isSuccess = true;
                result.payload = toConfirmation(confirmed.get(saveResults[j].getId()));
                continue;
            }
            List<String> messages = new List<String>();
            Boolean expected = true;
            for (Database.Error err : saveResults[j].getErrors()) {
                messages.add(err.getMessage());
                expected &= EXPECTED_REJECTION_CODES.contains(err.getStatusCode());
            }
            String message = String.join(messages, ' ');
            String code = message.contains(UNAVAILABLE_MESSAGE) ? ERROR_NOT_AVAILABLE : ERROR_DML;
            fail(result, code, message, bookings[j].Hotel_Suite__c, expected);
        }
        if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
        return results;
    }

    // ---------------------------------------------------------------------------------------------
    // Trigger rules (before insert: oldMap null; before update)
    // ---------------------------------------------------------------------------------------------

    public static void applyBookingRules(List<Suite_Booking__c> bookings, Map<Id, Suite_Booking__c> oldMap) {
        List<Suite_Booking__c> checked = new List<Suite_Booking__c>();
        Set<Id> suiteIds = new Set<Id>();
        Set<Id> updatingIds = new Set<Id>();
        Date windowStart;
        Date windowEnd;
        for (Suite_Booking__c booking : bookings) {
            Suite_Booking__c old = oldMap == null ? null : oldMap.get(booking.Id);
            if (!needsCheck(booking, old)) {
                continue;
            }
            checked.add(booking);
            suiteIds.add(booking.Hotel_Suite__c);
            if (booking.Id != null) {
                updatingIds.add(booking.Id);
            }
            windowStart = windowStart == null || booking.Check_In__c < windowStart ? booking.Check_In__c : windowStart;
            windowEnd = windowEnd == null || booking.Check_Out__c > windowEnd ? booking.Check_Out__c : windowEnd;
        }
        if (checked.isEmpty()) {
            return;
        }

        HotelBookingFactsSelector facts = HotelBookingFactsSelector.newInstance();
        Map<Id, Hotel_Suite__c> suites = facts.selectSuiteFacts(suiteIds);
        Map<Id, List<Suite_Booking__c>> held = groupBySuite(
            facts.selectConfirmedBookings(suiteIds, windowStart, windowEnd, updatingIds)
        );
        for (Suite_Booking__c booking : checked) {
            Hotel_Suite__c suite = suites.get(booking.Hotel_Suite__c);
            if (suite == null || !suite.Is_Active__c) {
                booking.Hotel_Suite__c.addError('This suite is not available for booking.');
                continue;
            }
            if (booking.Guests__c != null && suite.Max_Guests__c != null && booking.Guests__c > suite.Max_Guests__c) {
                booking.Guests__c.addError('This suite sleeps at most ' + suite.Max_Guests__c.intValue() + ' guests.');
                continue;
            }
            if (overlaps(held.get(suite.Id), booking.Check_In__c, booking.Check_Out__c)) {
                booking.addError(UNAVAILABLE_MESSAGE);
                continue;
            }
            Integer nights = booking.Check_In__c.daysBetween(booking.Check_Out__c);
            booking.Total_Price__c = nights > 0 ? suite.Nightly_Rate__c * nights : null;
            // Later bookings in the same save must not overlap this one either.
            if (!held.containsKey(suite.Id)) {
                held.put(suite.Id, new List<Suite_Booking__c>());
            }
            held.get(suite.Id).add(booking);
        }
    }

    private static Boolean needsCheck(Suite_Booking__c booking, Suite_Booking__c old) {
        if (
            booking.Status__c != STATUS_CONFIRMED ||
            booking.Hotel_Suite__c == null ||
            booking.Check_In__c == null ||
            booking.Check_Out__c == null
        ) {
            return false;
        }
        return old == null ||
            old.Status__c != booking.Status__c ||
            old.Hotel_Suite__c != booking.Hotel_Suite__c ||
            old.Check_In__c != booking.Check_In__c ||
            old.Check_Out__c != booking.Check_Out__c ||
            old.Guests__c != booking.Guests__c ||
            old.Total_Price__c != booking.Total_Price__c;
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    private static Integer nightsOrDefault(Integer nights) {
        return nights == null ? 1 : nights;
    }

    /** @description Null when the stay is valid, otherwise the reason. */
    private static String validateStay(Date checkIn, Integer nights, Integer guests) {
        if (checkIn == null) {
            return 'A check-in date is required.';
        }
        if (checkIn < Date.today()) {
            return 'The check-in date cannot be in the past.';
        }
        if (checkIn > Date.today().addDays(MAX_ADVANCE_DAYS)) {
            return 'Suites can be booked at most ' + MAX_ADVANCE_DAYS + ' days ahead.';
        }
        if (nights == null || nights < 1 || nights > MAX_NIGHTS) {
            return 'A stay lasts 1 to ' + MAX_NIGHTS + ' nights.';
        }
        if (guests != null && guests < 1) {
            return 'At least one guest is required.';
        }
        return null;
    }

    private static Id toSuiteId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id suiteId = Id.valueOf(value.trim());
            return suiteId.getSObjectType() == Hotel_Suite__c.SObjectType ? suiteId : null;
        } catch (StringException ex) {
            return null;
        }
    }

    private static Map<Id, List<Suite_Booking__c>> groupBySuite(List<Suite_Booking__c> bookings) {
        Map<Id, List<Suite_Booking__c>> bySuite = new Map<Id, List<Suite_Booking__c>>();
        for (Suite_Booking__c booking : bookings) {
            if (!bySuite.containsKey(booking.Hotel_Suite__c)) {
                bySuite.put(booking.Hotel_Suite__c, new List<Suite_Booking__c>());
            }
            bySuite.get(booking.Hotel_Suite__c).add(booking);
        }
        return bySuite;
    }

    /** @description True when any booking holds one of the nights in [checkIn, checkOut). */
    private static Boolean overlaps(List<Suite_Booking__c> bookings, Date checkIn, Date checkOut) {
        for (Suite_Booking__c booking : bookings == null ? new List<Suite_Booking__c>() : bookings) {
            if (booking.Check_In__c < checkOut && booking.Check_Out__c > checkIn) {
                return true;
            }
        }
        return false;
    }

    private static HotelSuiteOffer toOffer(Hotel_Suite__c suite, Integer nights) {
        HotelSuiteOffer offer = new HotelSuiteOffer();
        offer.suiteId = suite.Id;
        offer.suiteName = suite.Name;
        offer.hotelName = suite.Hotel_Name__c;
        offer.city = suite.City__c;
        offer.roomTier = suite.Room_Tier__c;
        offer.nightlyRate = suite.Nightly_Rate__c;
        offer.totalPrice = suite.Nightly_Rate__c * nights;
        offer.maxGuests = suite.Max_Guests__c == null ? null : suite.Max_Guests__c.intValue();
        return offer;
    }

    private static HotelBookingConfirmation toConfirmation(Suite_Booking__c booking) {
        HotelBookingConfirmation confirmation = new HotelBookingConfirmation();
        if (booking == null) {
            return confirmation;
        }
        confirmation.bookingId = booking.Id;
        confirmation.confirmationCode = booking.Name;
        confirmation.suiteName = booking.Hotel_Suite__r?.Name;
        confirmation.hotelName = booking.Hotel_Suite__r?.Hotel_Name__c;
        confirmation.checkInDate = booking.Check_In__c;
        confirmation.checkOutDate = booking.Check_Out__c;
        confirmation.totalPrice = booking.Total_Price__c;
        confirmation.currencyCode = UserInfo.getDefaultCurrency();
        return confirmation;
    }

    /**
     * @description Marks a booking request failed. Expected rejections log at WARN so the Admin Cockpit error
     * feed stays reserved for genuine system failures (ERROR).
     */
    private static void fail(
        BookHotelSuiteAction.Result result,
        String code,
        String message,
        Id recordId,
        Boolean isExpected
    ) {
        result.isSuccess = false;
        result.errorCode = code;
        result.errorMessage = message;
        String logMessage = 'BookHotelSuiteAction ' + code + ': ' + message;
        if (isExpected) {
            Logger.warn(logMessage, recordId);
        } else {
            Logger.error(logMessage, recordId);
        }
    }
}
