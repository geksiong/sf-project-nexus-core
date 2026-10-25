/**
 * @description Escalation to Tier 2. Every channel converges on one policy applied in the Case trigger:
 *  - Escalate Case flow / Agentforce / MCP: EscalateCaseAction sets Status = Escalated in user mode;
 *  - SLA violation: the entitlement process sets the SLA_Breached__c signal (system automation). The
 *    policy consumes it (stamps SLA_Violated_On__c, resets the signal), so every violation escalates;
 *  - Manual: an agent sets Status = Escalated on the record.
 *
 * Policy (before update): priority High, owner the Tier 2 queue (Omni-Channel routes it), timestamp,
 * and a default reason when none was given. Side effects (after update): a private case comment with
 * the reason, and case team provisioning (CaseTeamService).
 */
public with sharing class CaseEscalationService {
    public static final String STATUS_ESCALATED = 'Escalated';
    public static final String PRIORITY_HIGH = 'High';
    public static final String ESCALATION_QUEUE = 'Tier_2_Technical_Escalations';
    public static final String REASON_SLA_BREACH = 'SLA milestone violated.';
    public static final String REASON_MANUAL = 'Status set to Escalated.';

    public static final String ERROR_INVALID_INPUT = 'INVALID_INPUT';
    public static final String ERROR_NOT_FOUND = 'NOT_FOUND';
    public static final String ERROR_INVALID_STATE = 'INVALID_STATE';
    public static final String ERROR_DML = 'DML_ERROR';

    private static final Integer REASON_MAX_LENGTH = 255;

    /** @description DML status codes that are expected rejections (rules, locks, access), logged at WARN. */
    private static final Set<StatusCode> EXPECTED_REJECTION_CODES = new Set<StatusCode>{
        StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
        StatusCode.ENTITY_IS_LOCKED,
        StatusCode.INSUFFICIENT_ACCESS_OR_READONLY,
        StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
    };

    // ---------------------------------------------------------------------------------------------
    // Trigger entry points
    // ---------------------------------------------------------------------------------------------

    /** @description True when this save moves the case into Escalated. */
    public static Boolean isEscalation(Case c, Case old) {
        return old != null && c.Status == STATUS_ESCALATED && old.Status != STATUS_ESCALATED;
    }

    /** @description Before update: converts SLA violations into escalations and applies the policy. */
    public static void applyEscalationPolicy(List<Case> cases, Map<Id, Case> oldMap) {
        List<Case> escalating = new List<Case>();
        for (Case c : cases) {
            Case old = oldMap.get(c.Id);
            Boolean reasonProvided =
                String.isNotBlank(c.Escalation_Reason__c) && c.Escalation_Reason__c != old.Escalation_Reason__c;
            // One-shot signal: consume and reset it, so the next violated milestone flips it again.
            // (Changing the in-use entitlement process to stamp a field instead would need a new version.)
            Boolean violated = c.SLA_Breached__c && !old.SLA_Breached__c;
            if (violated) {
                c.SLA_Breached__c = false;
                c.SLA_Violated_On__c = System.now();
            }
            if (violated && !old.IsClosed && old.Status != STATUS_ESCALATED && c.Status != STATUS_ESCALATED) {
                c.Status = STATUS_ESCALATED;
                if (!reasonProvided) {
                    c.Escalation_Reason__c = REASON_SLA_BREACH;
                    reasonProvided = true;
                }
            }
            if (isEscalation(c, old)) {
                if (!reasonProvided) {
                    c.Escalation_Reason__c = REASON_MANUAL;
                }
                escalating.add(c);
            }
        }
        if (escalating.isEmpty()) {
            return;
        }

        Id queueId = ServiceDeskFactsSelector.newInstance().selectQueueId(ESCALATION_QUEUE);
        Datetime now = System.now();
        for (Case c : escalating) {
            if (queueId == null) {
                c.addError('Escalation is not configured: the ' + ESCALATION_QUEUE + ' queue does not exist.');
                continue;
            }
            c.Priority = PRIORITY_HIGH;
            c.OwnerId = queueId;
            c.Escalated_On__c = now;
        }
    }

    /** @description After update: records each escalation's reason as a private case comment. */
    public static void recordEscalations(List<Case> cases, Map<Id, Case> oldMap) {
        List<CaseComment> comments = new List<CaseComment>();
        for (Case c : cases) {
            if (isEscalation(c, oldMap.get(c.Id))) {
                comments.add(
                    new CaseComment(
                        ParentId = c.Id,
                        IsPublished = false,
                        CommentBody = 'Escalated to Tier 2: ' + c.Escalation_Reason__c
                    )
                );
            }
        }
        if (!comments.isEmpty()) {
            ServiceDeskDml.save(Database.insert(comments, false, AccessLevel.SYSTEM_MODE), 'Escalation comment');
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Invocable orchestration (EscalateCaseAction)
    // ---------------------------------------------------------------------------------------------

    /**
     * @description Escalates cases on request. The update runs in user mode, so the running user must be
     * allowed to edit the case; the trigger then applies the policy. Bulk-safe with partial success.
     */
    public static List<EscalateCaseAction.Result> escalateCases(List<EscalateCaseAction.Request> requests) {
        List<EscalateCaseAction.Result> results = new List<EscalateCaseAction.Result>();
        Map<Id, Integer> requestIndexByCaseId = new Map<Id, Integer>();
        Map<Integer, Id> smeByIndex = new Map<Integer, Id>();

        for (Integer i = 0; i < requests.size(); i++) {
            results.add(new EscalateCaseAction.Result());
            String inputError = validateRequest(requests[i], requestIndexByCaseId);
            if (inputError != null) {
                fail(results[i], ERROR_INVALID_INPUT, inputError, requests[i].caseId, true);
                continue;
            }
            requestIndexByCaseId.put(requests[i].caseId, i);
            if (String.isNotBlank(requests[i].smeUserId)) {
                smeByIndex.put(i, Id.valueOf(requests[i].smeUserId));
            }
        }

        if (!smeByIndex.isEmpty()) {
            Set<Id> activeUsers = ServiceDeskFactsSelector.newInstance()
                .selectActiveUserIds(new Set<Id>(smeByIndex.values()));
            for (Integer i : smeByIndex.keySet()) {
                if (!activeUsers.contains(smeByIndex.get(i))) {
                    requestIndexByCaseId.remove(requests[i].caseId);
                    fail(
                        results[i],
                        ERROR_INVALID_INPUT,
                        'Technical SME must be an active user.',
                        requests[i].caseId,
                        true
                    );
                }
            }
        }

        Map<Id, Case> casesById = new Map<Id, Case>(
            CasesSelector.newInstance().selectById(requestIndexByCaseId.keySet())
        );
        List<Case> updates = new List<Case>();
        List<Integer> updateIndexes = new List<Integer>();
        for (Id caseId : requestIndexByCaseId.keySet()) {
            Integer i = requestIndexByCaseId.get(caseId);
            Case existing = casesById.get(caseId);
            if (existing == null) {
                fail(results[i], ERROR_NOT_FOUND, 'Case not found or not accessible.', caseId, true);
            } else if (existing.IsClosed) {
                fail(results[i], ERROR_INVALID_STATE, 'Closed cases cannot be escalated.', caseId, true);
            } else if (existing.Status == STATUS_ESCALATED) {
                fail(
                    results[i],
                    ERROR_INVALID_STATE,
                    'Case ' + existing.CaseNumber + ' is already escalated.',
                    caseId,
                    true
                );
            } else {
                updates.add(
                    new Case(
                        Id = caseId,
                        Status = STATUS_ESCALATED,
                        Escalation_Reason__c = requests[i].reason.trim().abbreviate(REASON_MAX_LENGTH),
                        Technical_SME__c = smeByIndex.get(i)
                    )
                );
                updateIndexes.add(i);
            }
        }

        List<Database.SaveResult> saveResults = Database.update(updates, false, AccessLevel.USER_MODE);
        for (Integer j = 0; j < saveResults.size(); j++) {
            Integer i = updateIndexes[j];
            Case existing = casesById.get(updates[j].Id);
            if (saveResults[j].isSuccess()) {
                results[i].isSuccess = true;
                results[i].payload = new EscalateCaseAction.OutputPayload();
                results[i].payload.caseId = existing.Id;
                results[i].payload.caseNumber = existing.CaseNumber;
                results[i].payload.status = STATUS_ESCALATED;
            } else {
                List<String> messages = new List<String>();
                Boolean expected = true;
                for (Database.Error err : saveResults[j].getErrors()) {
                    messages.add(err.getMessage());
                    expected &= EXPECTED_REJECTION_CODES.contains(err.getStatusCode());
                }
                fail(results[i], ERROR_DML, String.join(messages, ' '), existing.Id, expected);
            }
        }

        if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
        return results;
    }

    private static String validateRequest(EscalateCaseAction.Request req, Map<Id, Integer> seen) {
        if (req.caseId == null) {
            return 'Case Id is required.';
        }
        if (req.caseId.getSObjectType() != Case.SObjectType) {
            return 'Case Id does not reference a Case.';
        }
        if (seen.containsKey(req.caseId)) {
            return 'Duplicate request for the same Case in one batch.';
        }
        if (String.isBlank(req.reason)) {
            return 'An escalation reason is required.';
        }
        if (String.isNotBlank(req.smeUserId)) {
            try {
                if (Id.valueOf(req.smeUserId).getSObjectType() != User.SObjectType) {
                    return 'Technical SME Id does not reference a User.';
                }
            } catch (StringException ex) {
                return 'Technical SME Id is not a valid record Id.';
            }
        }
        return null;
    }

    /**
     * @description Marks a request failed. Expected rejections log at WARN so the Admin Cockpit error
     * feed stays reserved for genuine system failures (ERROR).
     */
    private static void fail(
        EscalateCaseAction.Result result,
        String code,
        String message,
        Id recordId,
        Boolean isExpected
    ) {
        result.isSuccess = false;
        result.errorCode = code;
        result.errorMessage = message;
        String logMessage = 'EscalateCaseAction ' + code + ': ' + message;
        if (isExpected) {
            Logger.warn(logMessage, recordId);
        } else {
            Logger.error(logMessage, recordId);
        }
    }
}
