/**
 * @description Dynamic case team provisioning:
 *  - Escalation: the agent who owned the case joins as Escalating Agent, so they keep access and stay
 *    informed after ownership moves to the Tier 2 queue.
 *  - Technical SME: whoever is set in Technical_SME__c joins as Technical SME.
 *  - High priority: the account owner joins as Account Manager (read only).
 *
 * Membership is a consequence of rules, not a user choice, so it is written in system mode. It only
 * follows a case insert or update the running user was already allowed to make.
 */
public with sharing class CaseTeamService {
    public static final String ROLE_TECHNICAL_SME = 'Technical SME';
    public static final String ROLE_ESCALATING_AGENT = 'Escalating Agent';
    public static final String ROLE_ACCOUNT_MANAGER = 'Account Manager';
    public static final String PRIORITY_HIGH = 'High';

    /** @description After insert (oldMap null) and after update. */
    public static void provisionCaseTeams(List<Case> cases, Map<Id, Case> oldMap) {
        List<CaseTeamMember> members = planCaseTeamMembers(cases, oldMap);
        if (!members.isEmpty()) {
            PartialDml.save(Database.insert(members, false, AccessLevel.SYSTEM_MODE), 'Case team provisioning');
        } else if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
    }

    /** @description The case team members the rules require that do not exist yet (no DML). */
    @TestVisible
    private static List<CaseTeamMember> planCaseTeamMembers(List<Case> cases, Map<Id, Case> oldMap) {
        // Ordered by precedence: a user qualifying for several roles on one case gets the first.
        List<Membership> wanted = new List<Membership>();
        List<Membership> accountManagers = new List<Membership>();
        Set<Id> accountIds = new Set<Id>();

        for (Case c : cases) {
            Case old = oldMap == null ? null : oldMap.get(c.Id);
            if (c.Technical_SME__c != null && (old == null || old.Technical_SME__c != c.Technical_SME__c)) {
                wanted.add(new Membership(c.Id, c.Technical_SME__c, ROLE_TECHNICAL_SME));
            }
            if (
                old != null &&
                CaseEscalationService.isEscalation(c, old) &&
                old.OwnerId != null &&
                old.OwnerId.getSObjectType() == User.SObjectType
            ) {
                wanted.add(new Membership(c.Id, old.OwnerId, ROLE_ESCALATING_AGENT));
            }
            if (c.Priority == PRIORITY_HIGH && (old == null || old.Priority != PRIORITY_HIGH) && c.AccountId != null) {
                accountManagers.add(new Membership(c.Id, c.AccountId, ROLE_ACCOUNT_MANAGER));
                accountIds.add(c.AccountId);
            }
        }

        ServiceDeskFactsSelector facts = ServiceDeskFactsSelector.newInstance();
        if (!accountIds.isEmpty()) {
            Map<Id, Case> casesById = new Map<Id, Case>(cases);
            Map<Id, Id> owners = facts.selectActiveAccountOwnerIds(accountIds);
            for (Membership m : accountManagers) {
                Id ownerId = owners.get(m.memberId);
                if (ownerId != null && ownerId != casesById.get(m.caseId).OwnerId) {
                    wanted.add(new Membership(m.caseId, ownerId, ROLE_ACCOUNT_MANAGER));
                }
            }
        }
        List<CaseTeamMember> members = new List<CaseTeamMember>();
        if (wanted.isEmpty()) {
            return members;
        }

        Set<String> roleNames = new Set<String>();
        Set<Id> caseIds = new Set<Id>();
        for (Membership m : wanted) {
            roleNames.add(m.roleName);
            caseIds.add(m.caseId);
        }
        Map<String, Id> roleIds = facts.selectCaseTeamRoleIds(roleNames);
        Set<String> existing = facts.selectCaseTeamMemberKeys(caseIds);

        for (Membership m : wanted) {
            Id roleId = roleIds.get(m.roleName);
            if (roleId == null) {
                Logger.error('Case Team Role "' + m.roleName + '" is not configured; member not added', m.caseId);
                continue;
            }
            if (existing.add(m.caseId + ':' + m.memberId)) {
                members.add(new CaseTeamMember(ParentId = m.caseId, MemberId = m.memberId, TeamRoleId = roleId));
            }
        }
        return members;
    }

    private class Membership {
        private Id caseId;
        private Id memberId;
        private String roleName;

        private Membership(Id caseId, Id memberId, String roleName) {
            this.caseId = caseId;
            this.memberId = memberId;
            this.roleName = roleName;
        }
    }
}
