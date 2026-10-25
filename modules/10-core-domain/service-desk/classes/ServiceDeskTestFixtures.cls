/**
 * @description Shared fixtures for service desk tests: a Service Agent and a Technical SME user, the
 * case team roles, and entitlements on the Nexus Standard Support process.
 */
@IsTest
public class ServiceDeskTestFixtures {
    public static final String AGENT_LAST_NAME = 'NexusServiceAgent';
    public static final String SME_LAST_NAME = 'NexusTechnicalSme';
    public static final String SLA_PROCESS_NAME = 'Nexus Standard Support';

    /** @description Setup-object DML (users, roles, permissions) isolated from test data DML. */
    public static void createAgentsAndRoles() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ensureCaseTeamRoles();
            User agent = TestDataFactory.createTestUser('Standard User', null);
            agent.LastName = AGENT_LAST_NAME;
            User sme = TestDataFactory.createTestUser('Standard User', null);
            sme.LastName = SME_LAST_NAME;
            insert new List<User>{ agent, sme };
            assignServiceAgentAccess(agent.Id);
        }
    }

    /** @description Case Team Roles are org data, not metadata: create any the org does not have. */
    public static void ensureCaseTeamRoles() {
        Map<String, String> accessByRole = new Map<String, String>{
            CaseTeamService.ROLE_TECHNICAL_SME => 'Edit',
            CaseTeamService.ROLE_ESCALATING_AGENT => 'Edit',
            CaseTeamService.ROLE_ACCOUNT_MANAGER => 'Read'
        };
        for (CaseTeamRole role : [SELECT Name FROM CaseTeamRole WHERE Name IN :accessByRole.keySet()]) {
            accessByRole.remove(role.Name);
        }
        List<CaseTeamRole> missing = new List<CaseTeamRole>();
        for (String name : accessByRole.keySet()) {
            missing.add(new CaseTeamRole(Name = name, AccessLevel = accessByRole.get(name)));
        }
        insert missing;
    }

    /** @description Assigns PSG_Service_Agent exactly as the scratch org setup does. */
    public static void assignServiceAgentAccess(Id userId) {
        PermissionSetGroup psg = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'PSG_Service_Agent'];
        Test.calculatePermissionSetGroup(psg.Id);
        insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetGroupId = psg.Id);
    }

    public static Entitlement createEntitlement(Id accountId) {
        SlaProcess process = [SELECT Id FROM SlaProcess WHERE Name = :SLA_PROCESS_NAME AND IsActive = TRUE LIMIT 1];
        Entitlement ent = new Entitlement(
            Name = 'Standard Support',
            AccountId = accountId,
            SlaProcessId = process.Id,
            StartDate = Date.today().addDays(-1)
        );
        insert ent;
        return ent;
    }

    public static User getUser(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    public static Id escalationQueueId() {
        return [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :CaseEscalationService.ESCALATION_QUEUE]
        .Id;
    }

    public static Case newCase(Id accountId, Id ownerId, String priority) {
        return new Case(
            Subject = 'Nexus test case',
            Status = 'New',
            Origin = 'Phone',
            Priority = priority,
            AccountId = accountId,
            OwnerId = ownerId
        );
    }

    /** @description Case team as member Id to role name. */
    public static Map<Id, String> teamRoles(Id caseId) {
        Map<Id, String> roles = new Map<Id, String>();
        for (CaseTeamMember member : [SELECT MemberId, TeamRole.Name FROM CaseTeamMember WHERE ParentId = :caseId]) {
            roles.put(member.MemberId, member.TeamRole.Name);
        }
        return roles;
    }
}
