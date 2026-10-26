// Seeds the hotel suite catalogue and one booking for the Nexus Hotel Concierge (Phase 8, agentforce profile).
// Idempotent.
if (![SELECT Id FROM Hotel_Suite__c LIMIT 1].isEmpty()) {
    System.debug('Concierge seed data already present - skipped');
    return;
}
List<Hotel_Suite__c> suites = new List<Hotel_Suite__c>();
List<List<Object>> samples = new List<List<Object>>{
    // Suite, Hotel, City, Tier, Nightly rate, Max guests
    new List<Object>{ 'Harbour View Suite', 'Nexus Marina Hotel', 'Singapore', 'Executive', 420, 2 },
    new List<Object>{ 'Skyline Presidential Suite', 'Nexus Marina Hotel', 'Singapore', 'Presidential', 1250, 4 },
    new List<Object>{ 'Orchard Garden Suite', 'Nexus Orchard Hotel', 'Singapore', 'Deluxe', 290, 3 },
    new List<Object>{ 'Riverside Suite', 'Nexus Thames Hotel', 'London', 'Executive', 510, 2 },
    new List<Object>{ 'Royal Park Suite', 'Nexus Thames Hotel', 'London', 'Presidential', 1400, 4 },
    new List<Object>{ 'Bay Bridge Suite', 'Nexus Embarcadero Hotel', 'San Francisco', 'Deluxe', 380, 2 },
    new List<Object>{ 'Golden Gate Suite', 'Nexus Embarcadero Hotel', 'San Francisco', 'Executive', 640, 3 }
};
for (List<Object> s : samples) {
    suites.add(
        new Hotel_Suite__c(
            Name = (String) s[0],
            Hotel_Name__c = (String) s[1],
            City__c = (String) s[2],
            Room_Tier__c = (String) s[3],
            Nightly_Rate__c = (Integer) s[4],
            Max_Guests__c = (Integer) s[5],
            Is_Active__c = true
        )
    );
}
insert suites;
// The Harbour View Suite is taken for the first three nights of next week, so searches show availability rules.
Date nextWeek = Date.today().toStartOfWeek().addDays(7);
insert new Suite_Booking__c(
    Hotel_Suite__c = suites[0].Id,
    Check_In__c = nextWeek,
    Check_Out__c = nextWeek.addDays(3),
    Guests__c = 2,
    Guest_Name__c = 'Seed Guest',
    Status__c = 'Confirmed'
);
System.debug('Seeded ' + suites.size() + ' hotel suites and 1 booking');
