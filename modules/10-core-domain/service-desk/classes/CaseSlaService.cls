/**
 * @description SLA automation for the Nexus Standard Support entitlement process: links new cases to
 * their account's active entitlement and completes milestones as the case progresses.
 *
 * Milestone completion is platform bookkeeping that agents have no direct permission for, so it runs in
 * system mode; it only follows a case update the running user was already allowed to make.
 */
public with sharing class CaseSlaService {
    public static final String MILESTONE_FIRST_RESPONSE = 'First Response';
    public static final String MILESTONE_RESOLUTION = 'Resolution';
    public static final String STATUS_NEW = 'New';

    /**
     * @description Before insert (oldMap null) and before update: a case without an entitlement inherits
     * its account's active one when it is created with, or later given, an account.
     */
    public static void assignEntitlements(List<Case> cases, Map<Id, Case> oldMap) {
        List<Case> eligible = new List<Case>();
        Set<Id> accountIds = new Set<Id>();
        for (Case c : cases) {
            Case old = oldMap == null ? null : oldMap.get(c.Id);
            if (c.EntitlementId == null && c.AccountId != null && (old == null || old.AccountId != c.AccountId)) {
                eligible.add(c);
                accountIds.add(c.AccountId);
            }
        }
        if (eligible.isEmpty()) {
            return;
        }
        Map<Id, Id> entitlementIds = ServiceDeskFactsSelector.newInstance()
            .selectActiveEntitlementIdsByAccount(accountIds);
        for (Case c : eligible) {
            c.EntitlementId = entitlementIds.get(c.AccountId);
        }
    }

    /**
     * @description After update: moving into a working status completes First Response; closing completes
     * First Response (if still open) and Resolution. Escalating is not a response to the customer, so a move
     * into Escalated (manual or automatic on SLA violation) leaves First Response running.
     */
    public static void completeMilestones(List<Case> cases, Map<Id, Case> oldMap) {
        List<CaseMilestone> completions = planMilestoneCompletions(cases, oldMap);
        if (!completions.isEmpty()) {
            PartialDml.save(Database.update(completions, false, AccessLevel.SYSTEM_MODE), 'Milestone completion');
        }
    }

    /** @description The open milestones this save completes, stamped with the completion time (no DML). */
    @TestVisible
    private static List<CaseMilestone> planMilestoneCompletions(List<Case> cases, Map<Id, Case> oldMap) {
        List<CaseMilestone> completions = new List<CaseMilestone>();
        Map<Id, Set<String>> milestonesToComplete = new Map<Id, Set<String>>();
        for (Case c : cases) {
            Case old = oldMap.get(c.Id);
            if (c.EntitlementId == null) {
                continue;
            }
            Set<String> names = new Set<String>();
            Boolean closed = c.IsClosed && !old.IsClosed;
            Boolean responded =
                c.Status != old.Status &&
                c.Status != STATUS_NEW &&
                c.Status != CaseEscalationService.STATUS_ESCALATED;
            if (closed || responded) {
                names.add(MILESTONE_FIRST_RESPONSE);
            }
            if (closed) {
                names.add(MILESTONE_RESOLUTION);
            }
            if (!names.isEmpty()) {
                milestonesToComplete.put(c.Id, names);
            }
        }
        if (milestonesToComplete.isEmpty()) {
            return completions;
        }

        Map<Id, Map<String, Id>> openMilestones = ServiceDeskFactsSelector.newInstance()
            .selectOpenMilestoneIds(milestonesToComplete.keySet());
        Datetime now = System.now();
        for (Id caseId : milestonesToComplete.keySet()) {
            Map<String, Id> open = openMilestones.get(caseId);
            if (open == null) {
                continue;
            }
            for (String name : milestonesToComplete.get(caseId)) {
                if (open.containsKey(name)) {
                    completions.add(new CaseMilestone(Id = open.get(name), CompletionDate = now));
                }
            }
        }
        return completions;
    }
}
