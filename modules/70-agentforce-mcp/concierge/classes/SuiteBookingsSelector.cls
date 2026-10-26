/**
 * @description Data-access SOQL for Suite_Booking__c, WITH USER_MODE (bookings are private to their owner).
 */
public virtual with sharing class SuiteBookingsSelector {
    @TestVisible
    private static SuiteBookingsSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static SuiteBookingsSelector newInstance() {
        if (instance == null) {
            instance = new SuiteBookingsSelector();
        }
        return instance;
    }

    /** @description Bookings with their suite, for confirmations. */
    public virtual List<Suite_Booking__c> selectByIds(Set<Id> bookingIds) {
        if (bookingIds == null || bookingIds.isEmpty()) {
            return new List<Suite_Booking__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Check_In__c,
                Check_Out__c,
                Total_Price__c,
                Hotel_Suite__r.Name,
                Hotel_Suite__r.Hotel_Name__c
            FROM Suite_Booking__c
            WHERE Id IN :bookingIds
            WITH USER_MODE
        ];
    }
}
