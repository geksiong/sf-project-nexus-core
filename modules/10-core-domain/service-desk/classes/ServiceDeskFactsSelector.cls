/**
 * @description Facts the service desk rules evaluate: routing configuration, entitlements, milestones,
 * case team membership and active users.
 *
 * Escalation, SLA and case team rules must behave the same whoever saves the case (agents, the
 * entitlement process's automated user, integrations, agents acting through MCP), so this selector runs
 * WITH SYSTEM_MODE in a `without sharing` class (AGENTS.md 2.1, "Access Mode Follows Purpose").
 * Methods answer a narrow question and return Ids only; results never leave the services.
 */
public virtual without sharing class ServiceDeskFactsSelector {
    @TestVisible
    private static ServiceDeskFactsSelector instance;

    /** @description Returns the selector; tests replace it with a TestStub mock via `instance`. */
    public static ServiceDeskFactsSelector newInstance() {
        if (instance == null) {
            instance = new ServiceDeskFactsSelector();
        }
        return instance;
    }

    /** @description Case queue Id by developer name, or null when the queue does not exist. */
    public virtual Id selectQueueId(String developerName) {
        for (Group queue : [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :developerName
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            return queue.Id;
        }
        return null;
    }

    /** @description Case Team Role Ids by role name; roles that do not exist are absent. */
    public virtual Map<String, Id> selectCaseTeamRoleIds(Set<String> roleNames) {
        Map<String, Id> roleIds = new Map<String, Id>();
        if (roleNames == null || roleNames.isEmpty()) {
            return roleIds;
        }
        for (CaseTeamRole role : [SELECT Id, Name FROM CaseTeamRole WHERE Name IN :roleNames WITH SYSTEM_MODE]) {
            roleIds.put(role.Name, role.Id);
        }
        return roleIds;
    }

    /** @description Existing case team memberships as "caseId:memberId" keys. */
    public virtual Set<String> selectCaseTeamMemberKeys(Set<Id> caseIds) {
        Set<String> keys = new Set<String>();
        if (caseIds == null || caseIds.isEmpty()) {
            return keys;
        }
        for (CaseTeamMember member : [
            SELECT ParentId, MemberId
            FROM CaseTeamMember
            WHERE ParentId IN :caseIds
            WITH SYSTEM_MODE
        ]) {
            keys.add(member.ParentId + ':' + member.MemberId);
        }
        return keys;
    }

    /** @description Account Id to its owner's Id, for accounts whose owner is an active user. */
    public virtual Map<Id, Id> selectActiveAccountOwnerIds(Set<Id> accountIds) {
        Map<Id, Id> ownerIds = new Map<Id, Id>();
        if (accountIds == null || accountIds.isEmpty()) {
            return ownerIds;
        }
        for (Account acc : [
            SELECT Id, OwnerId
            FROM Account
            WHERE Id IN :accountIds AND Owner.IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            ownerIds.put(acc.Id, acc.OwnerId);
        }
        return ownerIds;
    }

    /** @description The subset of the given user Ids that are active users. */
    public virtual Set<Id> selectActiveUserIds(Set<Id> userIds) {
        Set<Id> active = new Set<Id>();
        if (userIds == null || userIds.isEmpty()) {
            return active;
        }
        for (User u : [SELECT Id FROM User WHERE Id IN :userIds AND IsActive = TRUE WITH SYSTEM_MODE]) {
            active.add(u.Id);
        }
        return active;
    }

    /**
     * @description Account Id to its active entitlement's Id. When an account has several active
     * entitlements, the one that started most recently wins.
     */
    public virtual Map<Id, Id> selectActiveEntitlementIdsByAccount(Set<Id> accountIds) {
        Map<Id, Id> entitlementIds = new Map<Id, Id>();
        if (accountIds == null || accountIds.isEmpty()) {
            return entitlementIds;
        }
        for (Entitlement ent : [
            SELECT Id, AccountId
            FROM Entitlement
            WHERE AccountId IN :accountIds AND Status = 'Active'
            WITH SYSTEM_MODE
            ORDER BY StartDate DESC NULLS LAST
        ]) {
            if (!entitlementIds.containsKey(ent.AccountId)) {
                entitlementIds.put(ent.AccountId, ent.Id);
            }
        }
        return entitlementIds;
    }

    /** @description Open (incomplete) case milestones: case Id to milestone name to CaseMilestone Id. */
    public virtual Map<Id, Map<String, Id>> selectOpenMilestoneIds(Set<Id> caseIds) {
        Map<Id, Map<String, Id>> milestoneIds = new Map<Id, Map<String, Id>>();
        if (caseIds == null || caseIds.isEmpty()) {
            return milestoneIds;
        }
        for (CaseMilestone milestone : [
            SELECT Id, CaseId, MilestoneType.Name
            FROM CaseMilestone
            WHERE CaseId IN :caseIds AND CompletionDate = NULL
            WITH SYSTEM_MODE
        ]) {
            if (!milestoneIds.containsKey(milestone.CaseId)) {
                milestoneIds.put(milestone.CaseId, new Map<String, Id>());
            }
            milestoneIds.get(milestone.CaseId).put(milestone.MilestoneType.Name, milestone.Id);
        }
        return milestoneIds;
    }
}
