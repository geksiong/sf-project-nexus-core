/**
 * @description Facts the booking rules evaluate. A suite is unavailable when anyone holds a confirmed booking for
 * the nights requested, yet bookings are private to their owners: availability and pricing must not depend on who
 * asks, so they read WITH SYSTEM_MODE in a `without sharing` class (AGENTS.md 2.1). Results are suite facts and
 * date ranges only (no guest data) and never leave HotelConciergeService.
 */
public virtual without sharing class HotelBookingFactsSelector {
    @TestVisible
    private static HotelBookingFactsSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static HotelBookingFactsSelector newInstance() {
        if (instance == null) {
            instance = new HotelBookingFactsSelector();
        }
        return instance;
    }

    /**
     * @description Rate, capacity and active flag of the given suites, locked (FOR UPDATE) until the transaction ends:
     * concurrent bookings of the same suite are serialised, so the overlap check that follows sees every committed
     * booking instead of racing a parallel save.
     */
    public virtual Map<Id, Hotel_Suite__c> selectSuiteFacts(Set<Id> suiteIds) {
        if (suiteIds == null || suiteIds.isEmpty()) {
            return new Map<Id, Hotel_Suite__c>();
        }
        return new Map<Id, Hotel_Suite__c>(
            [
                SELECT Id, Nightly_Rate__c, Max_Guests__c, Is_Active__c
                FROM Hotel_Suite__c
                WHERE Id IN :suiteIds
                WITH SYSTEM_MODE
                FOR UPDATE
            ]
        );
    }

    /**
     * @description Confirmed bookings of the given suites that overlap [fromDate, toDate), excluding the given
     * bookings (the records being updated). Returns only the suite and the dates.
     */
    public virtual List<Suite_Booking__c> selectConfirmedBookings(
        Set<Id> suiteIds,
        Date fromDate,
        Date toDate,
        Set<Id> excludeIds
    ) {
        if (suiteIds == null || suiteIds.isEmpty() || fromDate == null || toDate == null) {
            return new List<Suite_Booking__c>();
        }
        Set<Id> excluded = excludeIds == null ? new Set<Id>() : excludeIds;
        String confirmed = HotelConciergeService.STATUS_CONFIRMED;
        return [
            SELECT Hotel_Suite__c, Check_In__c, Check_Out__c
            FROM Suite_Booking__c
            WHERE
                Hotel_Suite__c IN :suiteIds
                AND Status__c = :confirmed
                AND Check_In__c < :toDate
                AND Check_Out__c > :fromDate
                AND Id NOT IN :excluded
            WITH SYSTEM_MODE
        ];
    }
}
