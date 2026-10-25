// Seeds the Service Desk demo (Phase 3). Idempotent: does nothing when the sample cases exist.
// Run after data/data-plan.json: sf apex run -o <alias> -f scripts/org-init/seed-service-desk.apex
if (![SELECT Id FROM Case WHERE Subject = 'Production line sensors offline' LIMIT 1].isEmpty()) {
    System.debug('Service desk seed data already present - skipped');
    return;
}

SlaProcess process = [SELECT Id FROM SlaProcess WHERE Name = 'Nexus Standard Support' AND IsActive = TRUE LIMIT 1];
Map<String, Account> accounts = new Map<String, Account>();
for (Account acc : [SELECT Id, Name FROM Account]) {
    accounts.put(acc.Name, acc);
}
Map<String, Contact> contacts = new Map<String, Contact>();
for (Contact con : [SELECT Id, Name FROM Contact]) {
    contacts.put(con.Name, con);
}

// Nexus Global Channel Partners deliberately has no entitlement: its cases run without SLA milestones.
List<Entitlement> entitlements = new List<Entitlement>();
for (
    String name : new List<String>{ 'Acme Global Manufacturing', 'Apex Healthcare Solutions', 'Globex Retail Group' }
) {
    entitlements.add(
        new Entitlement(
            Name = 'Standard Support - ' + name,
            AccountId = accounts.get(name).Id,
            SlaProcessId = process.Id,
            StartDate = Date.today().addDays(-30),
            EndDate = Date.today().addYears(1)
        )
    );
}
insert entitlements;

List<List<String>> samples = new List<List<String>>{
    // Subject, Account, Contact, Priority, Origin, Description
    new List<String>{
        'Production line sensors offline',
        'Acme Global Manufacturing',
        'Maria Chen',
        'High',
        'Phone',
        'All IoT sensors on line 3 stopped reporting at 06:00.'
    },
    new List<String>{
        'Gateway firmware update fails',
        'Acme Global Manufacturing',
        'David Okafor',
        'Medium',
        'Email',
        'Firmware 4.2 update rolls back after reboot.'
    },
    new List<String>{
        'Audit log export request',
        'Apex Healthcare Solutions',
        'Priya Raman',
        'Low',
        'Web',
        'Compliance team needs a 12-month audit log export.'
    },
    new List<String>{
        'POS integration timeouts',
        'Globex Retail Group',
        'Sarah Kim',
        'Medium',
        'Phone',
        'Store POS calls to the pricing API time out at peak hours.'
    },
    new List<String>{
        'Partner portal access request',
        'Nexus Global Channel Partners',
        'Tom Alvarez',
        'Low',
        'Web',
        'Two new partner reps need portal access.'
    }
};
List<Case> cases = new List<Case>();
for (List<String> s : samples) {
    cases.add(
        new Case(
            Subject = s[0],
            AccountId = accounts.get(s[1]).Id,
            ContactId = contacts.get(s[2]).Id,
            Priority = s[3],
            Origin = s[4],
            Description = s[5],
            Status = 'New'
        )
    );
}
// Route through the active assignment rule (Tier 1 Support queue), as the "Assign using active
// assignment rule" checkbox does in the UI.
Database.DMLOptions options = new Database.DMLOptions();
options.assignmentRuleHeader.useDefaultRule = true;
Database.insert(cases, options);

// Show the escalation flow end to end: the trigger moves this case to the Tier 2 queue.
update new Case(
    Id = cases[3].Id,
    Status = 'Escalated',
    Escalation_Reason__c = 'Peak-hour outage affecting all stores; needs API team.'
);
System.debug('Seeded ' + entitlements.size() + ' entitlements and ' + cases.size() + ' cases');
