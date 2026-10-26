/**
 * @description In-memory unit tests for concierge search, booking input validation and the booking rules
 * (selectors stubbed; no SOQL or DML).
 */
@IsTest
private class HotelConciergeServiceTest {
    private static final Id CHEAP = TestDataFactory.getFakeId(Hotel_Suite__c.SObjectType);
    private static final Id SMALL = TestDataFactory.getFakeId(Hotel_Suite__c.SObjectType);
    private static final Id PRICEY = TestDataFactory.getFakeId(Hotel_Suite__c.SObjectType);
    private static final Date CHECK_IN = Date.today().addDays(10);

    private static Hotel_Suite__c suite(Id suiteId, String city, Decimal rate, Integer maxGuests) {
        return new Hotel_Suite__c(
            Id = suiteId,
            Name = 'Suite ' + rate,
            Hotel_Name__c = 'Grand ' + city,
            City__c = city,
            Room_Tier__c = 'Deluxe',
            Nightly_Rate__c = rate,
            Max_Guests__c = maxGuests,
            Is_Active__c = true
        );
    }

    private static Suite_Booking__c booking(Id suiteId, Date checkIn, Integer nights) {
        return new Suite_Booking__c(
            Hotel_Suite__c = suiteId,
            Check_In__c = checkIn,
            Check_Out__c = checkIn.addDays(nights),
            Guests__c = 2,
            Status__c = HotelConciergeService.STATUS_CONFIRMED
        );
    }

    private static void mockSuites(List<Hotel_Suite__c> suites) {
        HotelSuitesSelector.instance = (HotelSuitesSelector) new TestStub()
            .returns('selectActiveByCities', suites)
            .create(HotelSuitesSelector.class);
    }

    private static void mockFacts(List<Hotel_Suite__c> suites, List<Suite_Booking__c> held) {
        HotelBookingFactsSelector.instance = (HotelBookingFactsSelector) new TestStub()
            .returns('selectSuiteFacts', new Map<Id, Hotel_Suite__c>(suites))
            .returns('selectConfirmedBookings', held)
            .create(HotelBookingFactsSelector.class);
    }

    private static HotelSearchAction.Request search(String city, Integer nights, Integer guests) {
        HotelSearchAction.Request req = new HotelSearchAction.Request();
        req.city = city;
        req.checkInDate = CHECK_IN;
        req.nights = nights;
        req.guests = guests;
        return req;
    }

    @IsTest
    static void searchOffersAvailableSuitesThatFitCheapestFirst() {
        List<Hotel_Suite__c> suites = new List<Hotel_Suite__c>{
            suite(CHEAP, 'Singapore', 200, 2),
            suite(SMALL, 'Singapore', 250, 1),
            suite(PRICEY, 'Singapore', 400, 4)
        };
        mockSuites(suites);
        // CHEAP is booked for the second night of the requested stay.
        mockFacts(suites, new List<Suite_Booking__c>{ booking(CHEAP, CHECK_IN.addDays(1), 1) });

        List<HotelSearchAction.Result> results = HotelSearchAction.execute(
            new List<HotelSearchAction.Request>{ search(' singapore ', 3, 2) }
        );

        Assert.isTrue(results[0].isSuccess, 'Error: ' + results[0].errorMessage);
        HotelSearchPayload payload = results[0].payload;
        Assert.areEqual(1, payload.suiteCount, 'Booked and too-small suites are not offered');
        Assert.areEqual(PRICEY, payload.suites[0].suiteId);
        Assert.areEqual(1200, payload.suites[0].totalPrice, '3 nights x 400');
        Assert.areEqual(CHECK_IN.addDays(3), payload.checkOutDate);
        Assert.areEqual('singapore', payload.city, 'City trimmed');
    }

    @IsTest
    static void searchDefaultsToOneNightAndCapsOffers() {
        List<Hotel_Suite__c> suites = new List<Hotel_Suite__c>();
        for (Integer i = 0; i < HotelConciergeService.MAX_OFFERS + 2; i++) {
            suites.add(suite(TestDataFactory.getFakeId(Hotel_Suite__c.SObjectType), 'Paris', 100 + i, null));
        }
        suites.add(suite(TestDataFactory.getFakeId(Hotel_Suite__c.SObjectType), 'London', 50, null));
        mockSuites(suites);
        mockFacts(suites, new List<Suite_Booking__c>());

        HotelSearchAction.Result result = HotelSearchAction.execute(
            new List<HotelSearchAction.Request>{ search('Paris', null, null) }
        )[0];

        Assert.isTrue(result.isSuccess);
        Assert.areEqual(1, result.payload.nights);
        Assert.areEqual(HotelConciergeService.MAX_OFFERS, result.payload.suiteCount);
        for (HotelSuiteOffer offer : result.payload.suites) {
            Assert.areEqual('Paris', offer.city, 'Other cities are not offered');
        }
    }

    @IsTest
    static void searchRejectsInvalidStays() {
        mockSuites(new List<Hotel_Suite__c>());
        mockFacts(new List<Hotel_Suite__c>(), new List<Suite_Booking__c>());
        HotelSearchAction.Request past = search('Rome', 1, 1);
        past.checkInDate = Date.today().addDays(-1);

        List<HotelSearchAction.Result> results = HotelSearchAction.execute(
            new List<HotelSearchAction.Request>{
                search(' ', 1, 1),
                past,
                search('Rome', HotelConciergeService.MAX_NIGHTS + 1, 1),
                search('Rome', 1, 0),
                search('Rome', 1, 1)
            }
        );

        Assert.areEqual('A city is required.', results[0].errorMessage);
        Assert.areEqual('The check-in date cannot be in the past.', results[1].errorMessage);
        Assert.isTrue(results[2].errorMessage.contains('1 to 30 nights'), 'Error: ' + results[2].errorMessage);
        Assert.areEqual('At least one guest is required.', results[3].errorMessage);
        for (Integer i = 0; i < 4; i++) {
            Assert.isFalse(results[i].isSuccess);
            Assert.areEqual(HotelConciergeService.ERROR_INVALID_INPUT, results[i].errorCode);
        }
        Assert.isTrue(results[4].isSuccess, 'Valid requests in the same batch still succeed');
        Assert.areEqual(0, results[4].payload.suiteCount);
    }

    @IsTest
    static void bookingRejectsInvalidInputWithoutDml() {
        BookHotelSuiteAction.Request wrongId = new BookHotelSuiteAction.Request();
        wrongId.suiteId = UserInfo.getUserId();
        wrongId.checkInDate = CHECK_IN;
        wrongId.nights = 2;
        BookHotelSuiteAction.Request garbage = new BookHotelSuiteAction.Request();
        garbage.suiteId = 'not-an-id';
        garbage.checkInDate = CHECK_IN;
        garbage.nights = 2;
        BookHotelSuiteAction.Request tooFar = new BookHotelSuiteAction.Request();
        tooFar.suiteId = CHEAP;
        tooFar.checkInDate = Date.today().addDays(HotelConciergeService.MAX_ADVANCE_DAYS + 1);
        tooFar.nights = 1;

        List<BookHotelSuiteAction.Result> results = BookHotelSuiteAction.execute(
            new List<BookHotelSuiteAction.Request>{ wrongId, garbage, tooFar }
        );

        Assert.areEqual('Suite Id does not reference a Hotel Suite.', results[0].errorMessage);
        Assert.areEqual('Suite Id does not reference a Hotel Suite.', results[1].errorMessage);
        Assert.isTrue(results[2].errorMessage.contains('days ahead'), 'Error: ' + results[2].errorMessage);
        for (BookHotelSuiteAction.Result result : results) {
            Assert.isFalse(result.isSuccess);
            Assert.areEqual(HotelConciergeService.ERROR_INVALID_INPUT, result.errorCode);
        }
    }

    @IsTest
    static void rulesPriceTheStayAndRejectUnavailableSuites() {
        Hotel_Suite__c inactive = suite(SMALL, 'Rome', 150, 2);
        inactive.Is_Active__c = false;
        List<Hotel_Suite__c> suites = new List<Hotel_Suite__c>{ suite(CHEAP, 'Rome', 200, 2), inactive };
        mockFacts(suites, new List<Suite_Booking__c>{ booking(PRICEY, CHECK_IN, 2) });
        Suite_Booking__c ok = booking(CHEAP, CHECK_IN, 3);
        Suite_Booking__c tooMany = booking(CHEAP, CHECK_IN.addDays(5), 1);
        tooMany.Guests__c = 3;
        Suite_Booking__c closed = booking(SMALL, CHECK_IN, 1);
        Suite_Booking__c unknown = booking(TestDataFactory.getFakeId(Hotel_Suite__c.SObjectType), CHECK_IN, 1);

        HotelConciergeService.applyBookingRules(new List<Suite_Booking__c>{ ok, tooMany, closed, unknown }, null);

        Assert.isFalse(ok.hasErrors());
        Assert.areEqual(600, ok.Total_Price__c, '3 nights x 200');
        Assert.areEqual('This suite sleeps at most 2 guests.', tooMany.getErrors()[0].getMessage());
        Assert.areEqual('This suite is not available for booking.', closed.getErrors()[0].getMessage());
        Assert.areEqual('This suite is not available for booking.', unknown.getErrors()[0].getMessage());
    }

    @IsTest
    static void rulesRejectOverlapsWithHeldAndSameSaveBookings() {
        List<Hotel_Suite__c> suites = new List<Hotel_Suite__c>{ suite(CHEAP, 'Rome', 200, 4) };
        mockFacts(suites, new List<Suite_Booking__c>{ booking(CHEAP, CHECK_IN, 2) });
        Suite_Booking__c clash = booking(CHEAP, CHECK_IN.addDays(1), 2);
        Suite_Booking__c checkOutDay = booking(CHEAP, CHECK_IN.addDays(2), 2);
        Suite_Booking__c sameSave = booking(CHEAP, CHECK_IN.addDays(3), 1);

        HotelConciergeService.applyBookingRules(new List<Suite_Booking__c>{ clash, checkOutDay, sameSave }, null);

        Assert.areEqual(HotelConciergeService.UNAVAILABLE_MESSAGE, clash.getErrors()[0].getMessage());
        Assert.isFalse(checkOutDay.hasErrors(), 'Arriving on the previous guest\'s check-out day is allowed');
        Assert.areEqual(
            HotelConciergeService.UNAVAILABLE_MESSAGE,
            sameSave.getErrors()[0].getMessage(),
            'Overlaps a booking accepted earlier in the same save'
        );
    }

    @IsTest
    static void rulesSkipCancelledAndUnchangedBookings() {
        TestStub facts = new TestStub().returns('selectSuiteFacts', new Map<Id, Hotel_Suite__c>());
        HotelBookingFactsSelector.instance = (HotelBookingFactsSelector) facts.create(HotelBookingFactsSelector.class);
        Suite_Booking__c cancelled = booking(CHEAP, CHECK_IN, 1);
        cancelled.Status__c = 'Cancelled';
        Suite_Booking__c unchanged = booking(CHEAP, CHECK_IN, 1);
        unchanged.Id = TestDataFactory.getFakeId(Suite_Booking__c.SObjectType);

        HotelConciergeService.applyBookingRules(
            new List<Suite_Booking__c>{ cancelled, unchanged },
            new Map<Id, Suite_Booking__c>{ unchanged.Id => unchanged.clone(true) }
        );

        Assert.areEqual(0, facts.callCount('selectSuiteFacts'), 'Nothing to check: no facts read');
    }
}
