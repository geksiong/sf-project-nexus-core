/**
 * @description CapEx request rules and the producer side of the ledger integration (ADR 0002):
 *  - Requests start as Draft with a positive amount; the approval process owns the status from there.
 *  - Once submitted or approved, the amount, department and title are frozen (record locks do not stop
 *    administrators, and the ledger must match what was approved).
 *  - Final approval marks the request Pending posting and publishes CapEx_Approved__e. The event is
 *    PublishAfterCommit, so a rolled-back approval never reaches the ledger.
 */
public with sharing class CapExService {
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String LEDGER_NOT_POSTED = 'Not Posted';
    public static final String LEDGER_PENDING = 'Pending';

    private static final Set<String> FROZEN_STATUSES = new Set<String>{ STATUS_SUBMITTED, STATUS_APPROVED };

    /** @description Before insert (oldMap null) and before update. */
    public static void validateRequests(List<CapEx_Request__c> requests, Map<Id, CapEx_Request__c> oldMap) {
        for (CapEx_Request__c request : requests) {
            CapEx_Request__c old = oldMap == null ? null : oldMap.get(request.Id);
            if (request.Total_Amount__c == null || request.Total_Amount__c <= 0) {
                request.Total_Amount__c.addError('The amount must be greater than zero.');
            }
            if (old == null) {
                if (request.Status__c != STATUS_DRAFT) {
                    request.Status__c.addError('New CapEx requests start as Draft and are submitted for approval.');
                }
                request.Ledger_Status__c = LEDGER_NOT_POSTED;
            } else if (
                FROZEN_STATUSES.contains(old.Status__c) &&
                (request.Total_Amount__c != old.Total_Amount__c ||
                request.Department__c != old.Department__c ||
                request.Title__c != old.Title__c)
            ) {
                request.addError(
                    'The amount, department and title cannot change once a request is ' +
                        old.Status__c +
                        '. Recall or reject it first.'
                );
            }
        }
    }

    /** @description Before update: an approval becomes Pending ledger posting. */
    public static void markApprovedForPosting(List<CapEx_Request__c> requests, Map<Id, CapEx_Request__c> oldMap) {
        for (CapEx_Request__c request : requests) {
            if (isApproval(request, oldMap.get(request.Id))) {
                request.Ledger_Status__c = LEDGER_PENDING;
            }
        }
    }

    /** @description After update: publishes CapEx_Approved__e for each approval (delivered after commit). */
    public static void publishApprovals(List<CapEx_Request__c> requests, Map<Id, CapEx_Request__c> oldMap) {
        List<CapEx_Approved__e> events = planApprovalEvents(requests, oldMap);
        if (events.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = EventBus.publish(events);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Logger.error(
                    'CapEx_Approved__e publish failed: ' + results[i].getErrors()[0].getMessage(),
                    Id.valueOf(events[i].CapEx_Request_Id__c)
                );
            }
        }
        if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
    }

    /** @description The approval events this save produces (no publish). */
    @TestVisible
    private static List<CapEx_Approved__e> planApprovalEvents(
        List<CapEx_Request__c> requests,
        Map<Id, CapEx_Request__c> oldMap
    ) {
        List<CapEx_Approved__e> events = new List<CapEx_Approved__e>();
        for (CapEx_Request__c request : requests) {
            if (isApproval(request, oldMap.get(request.Id))) {
                events.add(
                    new CapEx_Approved__e(
                        CapEx_Request_Id__c = request.Id,
                        Amount__c = request.Total_Amount__c,
                        Department__c = request.Department__c,
                        Approved_On__c = request.Approved_On__c == null ? System.now() : request.Approved_On__c
                    )
                );
            }
        }
        return events;
    }

    private static Boolean isApproval(CapEx_Request__c request, CapEx_Request__c old) {
        return request.Status__c == STATUS_APPROVED && old.Status__c != STATUS_APPROVED;
    }
}
