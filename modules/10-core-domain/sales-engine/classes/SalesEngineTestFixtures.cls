/**
 * @description Shared fixtures for sales engine tests: a three-level manager chain
 * (exec <- manager <- rep), deterministic approval tiers, and sales permission helpers.
 */
@IsTest
public class SalesEngineTestFixtures {
    public static final String EXEC_LAST_NAME = 'NexusExec';
    public static final String MANAGER_LAST_NAME = 'NexusManager';
    public static final String REP_LAST_NAME = 'NexusRep';
    public static final String SALES_ADMIN_LAST_NAME = 'NexusSalesAdmin';

    public static void createManagerChain() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User exec = TestDataFactory.createTestUser('Standard User', null);
            exec.LastName = EXEC_LAST_NAME;
            insert exec;

            User manager = TestDataFactory.createTestUser('Standard User', null);
            manager.LastName = MANAGER_LAST_NAME;
            manager.ManagerId = exec.Id;
            insert manager;

            User rep = TestDataFactory.createTestUser('Standard User', null);
            rep.LastName = REP_LAST_NAME;
            rep.ManagerId = manager.Id;
            insert rep;

            assignSalesRepAccess(rep.Id);

            // Selectors run WITH USER_MODE, so tests act as an admin that holds the sales permissions.
            // (Assigning permissions to the already-running user does not take effect within a test.)
            User salesAdmin = TestDataFactory.createTestUser('System Administrator', null);
            salesAdmin.LastName = SALES_ADMIN_LAST_NAME;
            insert salesAdmin;
            assignSalesRepAccess(salesAdmin.Id);
            insert new PermissionSetAssignment(
                AssigneeId = salesAdmin.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'PS_Sales_Admin']
                .Id
            );
        }
    }

    public static User salesAdmin() {
        return getUser(SALES_ADMIN_LAST_NAME);
    }

    public static User getUser(String lastName) {
        return [SELECT Id, ManagerId FROM User WHERE LastName = :lastName LIMIT 1];
    }

    /** @description Pins the tier thresholds so tests do not depend on org-configured CMDT values. */
    public static void useStandardTiers() {
        OpportunityService.approvalTiers = new List<Discount_Approval_Tier__mdt>{
            new Discount_Approval_Tier__mdt(
                DeveloperName = 'Tier_1',
                Discount_Threshold__c = 10,
                Approval_Tier__c = 'Tier 1'
            ),
            new Discount_Approval_Tier__mdt(
                DeveloperName = 'Tier_2',
                Discount_Threshold__c = 25,
                Approval_Tier__c = 'Tier 2'
            )
        };
    }

    /** @description Assigns PSG_Sales_Representative exactly as the scratch org setup does. */
    public static void assignSalesRepAccess(Id userId) {
        PermissionSetGroup psg = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'PSG_Sales_Representative'];
        Test.calculatePermissionSetGroup(psg.Id);
        Boolean alreadyAssigned = ![
                SELECT Id
                FROM PermissionSetAssignment
                WHERE AssigneeId = :userId AND PermissionSetGroupId = :psg.Id
            ]
            .isEmpty();
        if (!alreadyAssigned) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetGroupId = psg.Id);
        }
    }
}
