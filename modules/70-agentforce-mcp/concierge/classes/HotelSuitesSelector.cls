/**
 * @description Data-access SOQL for Hotel_Suite__c, WITH USER_MODE: the concierge offers only suites the running
 * user can see (the catalogue is public read only).
 */
public virtual with sharing class HotelSuitesSelector {
    @TestVisible
    private static HotelSuitesSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static HotelSuitesSelector newInstance() {
        if (instance == null) {
            instance = new HotelSuitesSelector();
        }
        return instance;
    }

    /**
     * @description Active suites in the given cities (case-insensitive), cheapest first. The limit covers the whole
     * catalogue of a few cities; callers cap the offers per request (HotelConciergeService.MAX_OFFERS).
     */
    public virtual List<Hotel_Suite__c> selectActiveByCities(Set<String> cities) {
        if (cities == null || cities.isEmpty()) {
            return new List<Hotel_Suite__c>();
        }
        return [
            SELECT Id, Name, Hotel_Name__c, City__c, Room_Tier__c, Nightly_Rate__c, Max_Guests__c
            FROM Hotel_Suite__c
            WHERE Is_Active__c = TRUE AND City__c IN :cities
            WITH USER_MODE
            ORDER BY Nightly_Rate__c ASC, Name ASC
            LIMIT 2000
        ];
    }
}
