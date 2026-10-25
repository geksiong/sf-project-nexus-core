/**
 * @description In-memory unit tests for CapEx request rules and approval event planning (no SOQL/DML).
 */
@IsTest
private class CapExServiceTest {
    private static CapEx_Request__c request(String status, Decimal amount) {
        return new CapEx_Request__c(
            Id = TestDataFactory.getFakeId(CapEx_Request__c.SObjectType),
            Title__c = 'Switches',
            Department__c = 'IT Infrastructure',
            Total_Amount__c = amount,
            Status__c = status
        );
    }

    private static String errors(SObject record) {
        List<String> messages = new List<String>();
        for (Database.Error err : record.getErrors()) {
            messages.add(err.getMessage());
        }
        return String.join(messages, ' | ');
    }

    private static void validate(CapEx_Request__c changed, CapEx_Request__c old) {
        CapExService.validateRequests(
            new List<CapEx_Request__c>{ changed },
            old == null ? null : new Map<Id, CapEx_Request__c>{ old.Id => old }
        );
    }

    @IsTest
    static void newRequestsStartAsDraftWithPositiveAmount() {
        CapEx_Request__c valid = request(CapExService.STATUS_DRAFT, 1000);
        valid.Ledger_Status__c = 'Posted';
        CapEx_Request__c zero = request(CapExService.STATUS_DRAFT, 0);
        CapEx_Request__c preApproved = request(CapExService.STATUS_APPROVED, 1000);

        CapExService.validateRequests(new List<CapEx_Request__c>{ valid, zero, preApproved }, null);

        Assert.isFalse(valid.hasErrors(), errors(valid));
        Assert.areEqual(CapExService.LEDGER_NOT_POSTED, valid.Ledger_Status__c, 'Ledger status cannot be preset');
        Assert.isTrue(errors(zero).contains('greater than zero'), errors(zero));
        Assert.isTrue(errors(preApproved).contains('start as Draft'), errors(preApproved));
    }

    @IsTest
    static void submittedAndApprovedRequestsFreezeAmountDepartmentAndTitle() {
        for (String status : new List<String>{ CapExService.STATUS_SUBMITTED, CapExService.STATUS_APPROVED }) {
            CapEx_Request__c old = request(status, 1000);
            CapEx_Request__c raised = old.clone(true);
            raised.Total_Amount__c = 5000;
            validate(raised, old);
            Assert.isTrue(errors(raised).contains('cannot change'), status + ': ' + errors(raised));

            CapEx_Request__c justified = old.clone(true);
            justified.Description__c = 'More detail';
            validate(justified, old);
            Assert.isFalse(justified.hasErrors(), status + ': ' + errors(justified));
        }

        CapEx_Request__c draft = request(CapExService.STATUS_DRAFT, 1000);
        CapEx_Request__c edited = draft.clone(true);
        edited.Department__c = 'Customer Care';
        validate(edited, draft);
        Assert.isFalse(edited.hasErrors(), 'Drafts are editable: ' + errors(edited));
    }

    @IsTest
    static void approvalMarksPendingAndPlansOneEvent() {
        CapEx_Request__c submitted = request(CapExService.STATUS_SUBMITTED, 1250.50);
        CapEx_Request__c approved = submitted.clone(true);
        approved.Status__c = CapExService.STATUS_APPROVED;
        approved.Approved_On__c = Datetime.newInstanceGmt(2026, 10, 1, 9, 0, 0);
        CapEx_Request__c unchanged = request(CapExService.STATUS_APPROVED, 10);
        Map<Id, CapEx_Request__c> oldMap = new Map<Id, CapEx_Request__c>{
            submitted.Id => submitted,
            unchanged.Id => unchanged.clone(true)
        };

        CapExService.markApprovedForPosting(new List<CapEx_Request__c>{ approved, unchanged }, oldMap);
        List<CapEx_Approved__e> events = CapExService.planApprovalEvents(
            new List<CapEx_Request__c>{ approved, unchanged },
            oldMap
        );

        Assert.areEqual(CapExService.LEDGER_PENDING, approved.Ledger_Status__c);
        Assert.isNull(unchanged.Ledger_Status__c, 'Already approved: no new posting');
        Assert.areEqual(1, events.size());
        Assert.areEqual(String.valueOf(approved.Id), events[0].CapEx_Request_Id__c);
        Assert.areEqual(1250.50, events[0].Amount__c);
        Assert.areEqual('IT Infrastructure', events[0].Department__c);
        Assert.areEqual(approved.Approved_On__c, events[0].Approved_On__c);
    }
}
