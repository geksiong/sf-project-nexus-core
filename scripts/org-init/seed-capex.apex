// Seeds the Back-Office CapEx demo (Phase 4). Idempotent: does nothing when the sample requests exist.
// Run after the persona setup: sf apex run -o <alias> -f scripts/org-init/seed-capex.apex
// Approved requests go through the real approval process, so their CapEx_Approved__e events are consumed
// and (with ERP_Ledger_Setting.Default.Simulate__c on) posted to the ledger asynchronously.
if (![SELECT Id FROM CapEx_Request__c WHERE Title__c = 'Field service van fleet refresh' LIMIT 1].isEmpty()) {
    System.debug('CapEx seed data already present - skipped');
    return;
}

List<List<String>> samples = new List<List<String>>{
    // Title, Department, Amount, Outcome (Draft / Submitted / Approved / Rejected), Description
    new List<String>{
        'Field service van fleet refresh',
        'Field Operations',
        '185000',
        'Approved',
        'Replace 12 vans past 250,000 km.'
    },
    new List<String>{
        'Core network switch upgrade',
        'IT Infrastructure',
        '72000',
        'Approved',
        'End-of-support core switches in both data centres.'
    },
    new List<String>{
        'Contact center headset replacement',
        'Customer Care',
        '18500',
        'Submitted',
        'Noise-cancelling headsets for 120 agents.'
    },
    new List<String>{
        'Data center UPS batteries',
        'IT Infrastructure',
        '46000',
        'Draft',
        'Battery strings reach end of life next quarter.'
    },
    new List<String>{
        'Ruggedized tablets for technicians',
        'Field Operations',
        '39000',
        'Rejected',
        'Pilot for 30 technicians.'
    }
};
List<CapEx_Request__c> requests = new List<CapEx_Request__c>();
for (List<String> s : samples) {
    requests.add(
        new CapEx_Request__c(
            Title__c = s[0],
            Department__c = s[1],
            Total_Amount__c = Decimal.valueOf(s[2]),
            Description__c = s[4]
        )
    );
}
insert requests;

// Submit (as the owner) and decide (System Administrators may act on any approval request).
List<Approval.ProcessSubmitRequest> submissions = new List<Approval.ProcessSubmitRequest>();
for (Integer i = 0; i < samples.size(); i++) {
    if (samples[i][3] != 'Draft') {
        Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
        submit.setObjectId(requests[i].Id);
        submit.setComments('Seeded demo request');
        submissions.add(submit);
    }
}
Approval.process(submissions);

Map<Id, String> outcomeByRequest = new Map<Id, String>();
for (Integer i = 0; i < samples.size(); i++) {
    outcomeByRequest.put(requests[i].Id, samples[i][3]);
}
List<Approval.ProcessWorkitemRequest> decisions = new List<Approval.ProcessWorkitemRequest>();
for (ProcessInstanceWorkitem item : [
    SELECT Id, ProcessInstance.TargetObjectId
    FROM ProcessInstanceWorkitem
    WHERE ProcessInstance.TargetObjectId IN :outcomeByRequest.keySet()
]) {
    String outcome = outcomeByRequest.get(item.ProcessInstance.TargetObjectId);
    if (outcome == 'Approved' || outcome == 'Rejected') {
        Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
        decision.setWorkitemId(item.Id);
        decision.setAction(outcome == 'Approved' ? 'Approve' : 'Reject');
        decision.setComments('Seeded decision');
        decisions.add(decision);
    }
}
Approval.process(decisions);
System.debug('Seeded ' + requests.size() + ' CapEx requests (' + decisions.size() + ' decided)');
