/**
 * @description Shared fixtures for CapEx tests: a rep reporting to a manager (role hierarchy), a peer rep,
 * a finance controller (outside the sales hierarchy) and an operations admin.
 */
@IsTest
public class CapExTestFixtures {
    public static final String REP = 'NexusCapExRep';
    public static final String PEER = 'NexusCapExPeer';
    public static final String MANAGER = 'NexusCapExManager';
    public static final String FINANCE = 'NexusCapExFinance';
    public static final String OPS_ADMIN = 'NexusCapExOpsAdmin';

    public static void createUsers() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User manager = user(MANAGER, 'Sales_Manager');
            User finance = user(FINANCE, 'Finance_Controller');
            User opsAdmin = user(OPS_ADMIN, 'Sales_Manager');
            insert new List<User>{ manager, finance, opsAdmin };
            User rep = user(REP, 'Sales_Representative');
            rep.ManagerId = manager.Id;
            User peer = user(PEER, 'Sales_Representative');
            peer.ManagerId = manager.Id;
            insert new List<User>{ rep, peer };

            Map<String, Id> permissionSets = new Map<String, Id>();
            for (PermissionSet ps : [
                SELECT Id, Name
                FROM PermissionSet
                WHERE Name IN ('PS_CapEx_Submitter', 'PS_CapEx_Reviewer', 'PS_CapEx_Admin')
            ]) {
                permissionSets.put(ps.Name, ps.Id);
            }
            insert new List<PermissionSetAssignment>{
                assign(rep.Id, permissionSets.get('PS_CapEx_Submitter')),
                assign(peer.Id, permissionSets.get('PS_CapEx_Submitter')),
                assign(manager.Id, permissionSets.get('PS_CapEx_Reviewer')),
                assign(finance.Id, permissionSets.get('PS_CapEx_Reviewer')),
                assign(opsAdmin.Id, permissionSets.get('PS_CapEx_Admin'))
            };
        }
    }

    private static User user(String lastName, String role) {
        User u = TestDataFactory.createTestUser('Standard User', role);
        u.LastName = lastName;
        return u;
    }

    private static PermissionSetAssignment assign(Id userId, Id permissionSetId) {
        return new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
    }

    public static User getUser(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    public static CapEx_Request__c newRequest(Id ownerId, Decimal amount) {
        return new CapEx_Request__c(
            Title__c = 'Test equipment',
            Department__c = 'IT Infrastructure',
            Total_Amount__c = amount,
            OwnerId = ownerId
        );
    }

    /** @description The rep submits the request and the manager decides, as in the UI. */
    public static void submitAndDecide(Id requestId, String action) {
        System.runAs(getUser(REP)) {
            Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
            submit.setObjectId(requestId);
            Approval.process(submit);
        }
        Id workItemId = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :requestId].Id;
        System.runAs(getUser(MANAGER)) {
            Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
            decision.setWorkitemId(workItemId);
            decision.setAction(action);
            Approval.process(decision);
        }
    }

    public static Ledger_Entry__c ledgerEntry(Id requestId) {
        return [
            SELECT Id, Status__c, ERP_Reference__c, Attempts__c, Last_Error__c, Posted_On__c, Amount__c
            FROM Ledger_Entry__c
            WHERE CapEx_Request__c = :requestId
        ];
    }

    /** @description Drives an ERP outage to its final attempt (tests cannot chain queueables). */
    public static void runDeferredJobs() {
        while (!LedgerPostingJob.deferredInTests.isEmpty()) {
            LedgerPostingJob.deferredInTests.remove(0).execute(null);
        }
    }
}
