// Seeds the Experience Cloud demos (Phase 6, full profile). Idempotent: does nothing when the sample
// articles exist. Articles go live through the Portal Content Approval process, exactly as authors publish.
if (![SELECT Id FROM Portal_Article__c WHERE Name = 'Spring spa escape' LIMIT 1].isEmpty()) {
    System.debug('Portal seed data already present - skipped');
    return;
}
List<List<String>> samples = new List<List<String>>{
    // Title, Category, Summary, Body, Publish? (Y/N)
    new List<String>{
        'Spring spa escape',
        'Offers',
        'Two nights, spa access and breakfast for two.',
        'Book by 31 May for stays until the end of June. Subject to availability.',
        'Y'
    },
    new List<String>{
        'Harbour lights festival',
        'Events',
        'Three evenings of music and food on the waterfront.',
        'Guests receive priority entry and a welcome drink at the hotel bar.',
        'Y'
    },
    new List<String>{
        'Packing for a city break',
        'Travel Tips',
        'What our concierges always recommend.',
        'Comfortable shoes, a light rain jacket and a reusable bottle.',
        'Y'
    },
    new List<String>{
        'Summer rooftop menu (draft)',
        'Offers',
        'Not yet approved.',
        'This draft must never appear on the public site.',
        'N'
    }
};
List<Portal_Article__c> articles = new List<Portal_Article__c>();
for (List<String> s : samples) {
    articles.add(new Portal_Article__c(Name = s[0], Category__c = s[1], Summary__c = s[2], Body__c = s[3]));
}
insert articles;

List<Approval.ProcessSubmitRequest> submissions = new List<Approval.ProcessSubmitRequest>();
for (Integer i = 0; i < samples.size(); i++) {
    if (samples[i][4] == 'Y') {
        Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
        submit.setObjectId(articles[i].Id);
        submissions.add(submit);
    }
}
Approval.process(submissions);
List<Approval.ProcessWorkitemRequest> approvals = new List<Approval.ProcessWorkitemRequest>();
for (ProcessInstanceWorkitem item : [
    SELECT Id
    FROM ProcessInstanceWorkitem
    WHERE ProcessInstance.TargetObjectId IN :new Map<Id, Portal_Article__c>(articles).keySet()
]) {
    Approval.ProcessWorkitemRequest approve = new Approval.ProcessWorkitemRequest();
    approve.setWorkitemId(item.Id);
    approve.setAction('Approve');
    approvals.add(approve);
}
Approval.process(approvals);
System.debug('Seeded ' + articles.size() + ' portal articles (' + approvals.size() + ' published)');
