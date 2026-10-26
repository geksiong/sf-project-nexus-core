/**
 * @description End-to-end concierge tests with real DML: the actions run as guest users holding
 * PS_Hotel_Concierge_Guest, bookings are private, and availability still counts other guests' bookings
 * (HotelBookingFactsSelector, system mode).
 */
@IsTest
private class HotelConciergeIntegrationTest {
    private static final Date CHECK_IN = Date.today().addDays(14);

    @TestSetup
    static void setup() {
        // Users and permission set assignments are setup objects: insert them in their own context (mixed DML).
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> guests = new List<User>{
                TestDataFactory.createTestUser('Standard User', null),
                TestDataFactory.createTestUser('Standard User', null)
            };
            guests[0].LastName = 'GuestOne';
            guests[1].LastName = 'GuestTwo';
            insert guests;
            Id permSetId = [SELECT Id FROM PermissionSet WHERE Name = 'PS_Hotel_Concierge_Guest'].Id;
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = guests[0].Id, PermissionSetId = permSetId),
                new PermissionSetAssignment(AssigneeId = guests[1].Id, PermissionSetId = permSetId)
            };
        }
        insert new List<Hotel_Suite__c>{
            new Hotel_Suite__c(
                Name = 'Harbour Suite',
                Hotel_Name__c = 'Nexus Marina Hotel',
                City__c = 'Singapore',
                Room_Tier__c = 'Executive',
                Nightly_Rate__c = 300,
                Max_Guests__c = 2,
                Is_Active__c = true
            ),
            new Hotel_Suite__c(
                Name = 'Garden Suite',
                Hotel_Name__c = 'Nexus Orchard Hotel',
                City__c = 'Singapore',
                Room_Tier__c = 'Deluxe',
                Nightly_Rate__c = 450,
                Max_Guests__c = 4,
                Is_Active__c = true
            )
        };
    }

    private static User guest(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    private static Id suiteId(String name) {
        return [SELECT Id FROM Hotel_Suite__c WHERE Name = :name].Id;
    }

    private static BookHotelSuiteAction.Result book(Id suite, Date checkIn, Integer nights) {
        BookHotelSuiteAction.Request req = new BookHotelSuiteAction.Request();
        req.suiteId = suite;
        req.checkInDate = checkIn;
        req.nights = nights;
        req.guests = 2;
        return BookHotelSuiteAction.execute(new List<BookHotelSuiteAction.Request>{ req })[0];
    }

    private static HotelSearchPayload searchSingapore(Integer nights) {
        HotelSearchAction.Request req = new HotelSearchAction.Request();
        req.city = 'singapore';
        req.checkInDate = CHECK_IN;
        req.nights = nights;
        HotelSearchAction.Result result = HotelSearchAction.execute(new List<HotelSearchAction.Request>{ req })[0];
        Assert.isTrue(result.isSuccess, 'Error: ' + result.errorMessage);
        return result.payload;
    }

    @IsTest
    static void guestSearchesAndBooksASuite() {
        Id harbour = suiteId('Harbour Suite');
        HotelSearchPayload before;
        BookHotelSuiteAction.Result result;
        System.runAs(guest('GuestOne')) {
            Test.startTest();
            before = searchSingapore(2);
            result = book(harbour, CHECK_IN, 2);
            Test.stopTest();
        }

        Assert.areEqual(2, before.suiteCount);
        Assert.areEqual('Harbour Suite', before.suites[0].suiteName, 'Cheapest first');
        Assert.isTrue(result.isSuccess, 'Error: ' + result.errorMessage);
        Assert.isTrue(result.payload.confirmationCode.startsWith('NXB-'), result.payload.confirmationCode);
        Assert.areEqual('Nexus Marina Hotel', result.payload.hotelName);
        Assert.areEqual(600, result.payload.totalPrice, '2 nights x 300');
        Assert.isNotNull(result.payload.currencyCode);
        Assert.areEqual(CHECK_IN.addDays(2), result.payload.checkOutDate);
        Suite_Booking__c saved = [SELECT Guest_Name__c, Status__c FROM Suite_Booking__c];
        Assert.areEqual('Confirmed', saved.Status__c);
        Assert.isTrue(saved.Guest_Name__c.contains('GuestOne'), 'Defaults to the booking user');
    }

    @IsTest
    static void anotherGuestsBookingMakesTheSuiteUnavailable() {
        Id harbour = suiteId('Harbour Suite');
        System.runAs(guest('GuestOne')) {
            Assert.isTrue(book(harbour, CHECK_IN, 3).isSuccess);
        }

        BookHotelSuiteAction.Result clash;
        HotelSearchPayload offers;
        Integer visibleBookings;
        System.runAs(guest('GuestTwo')) {
            Test.startTest();
            visibleBookings = [SELECT COUNT() FROM Suite_Booking__c WITH USER_MODE];
            clash = book(harbour, CHECK_IN.addDays(1), 1);
            offers = searchSingapore(1);
            Test.stopTest();
        }

        Assert.areEqual(0, visibleBookings, 'Bookings are private to the guest who made them');
        Assert.isFalse(clash.isSuccess);
        Assert.areEqual(HotelConciergeService.ERROR_NOT_AVAILABLE, clash.errorCode);
        Assert.areEqual(1, offers.suiteCount, 'The booked suite is not offered to anyone');
        Assert.areEqual('Garden Suite', offers.suites[0].suiteName);
    }

    @IsTest
    static void cancellingReleasesTheSuiteAndPriceIsNotEditable() {
        Id harbour = suiteId('Harbour Suite');
        BookHotelSuiteAction.Result rebooked;
        Decimal priceAfterEdit;
        System.runAs(guest('GuestOne')) {
            Test.startTest();
            Suite_Booking__c booking = new Suite_Booking__c(Id = book(harbour, CHECK_IN, 1).payload.bookingId);
            booking.Total_Price__c = 1;
            update booking;
            priceAfterEdit = [SELECT Total_Price__c FROM Suite_Booking__c WHERE Id = :booking.Id].Total_Price__c;
            booking.Status__c = 'Cancelled';
            update booking;
            rebooked = book(harbour, CHECK_IN, 1);
            Test.stopTest();
        }

        Assert.areEqual(300, priceAfterEdit, 'The rules reprice an edited booking');
        Assert.isTrue(rebooked.isSuccess, 'Error: ' + rebooked.errorMessage);
        Assert.areEqual(300, rebooked.payload.totalPrice);
    }

    @IsTest
    static void usersWithoutThePermissionSetCannotBook() {
        User outsider = TestDataFactory.createTestUser('Standard User', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert outsider;
        }
        Id harbour = suiteId('Harbour Suite');
        BookHotelSuiteAction.Result result;
        System.runAs(outsider) {
            Test.startTest();
            result = book(harbour, CHECK_IN, 1);
            Test.stopTest();
        }

        Assert.isFalse(result.isSuccess);
        Assert.areEqual(HotelConciergeService.ERROR_DML, result.errorCode, result.errorMessage);
    }
}
