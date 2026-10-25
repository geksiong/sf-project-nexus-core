/**
 * @description Domain service for the Enterprise Sales & Pipeline Engine (Demo App 1).
 * Owns discount approval policy, stage-gate validations, and the deal closing orchestration.
 */
public with sharing class OpportunityService {
    public static final String STAGE_CLOSED_WON = 'Closed Won';
    public static final String STAGE_CLOSED_LOST = 'Closed Lost';
    public static final String OUTCOME_WON = 'Won';
    public static final String OUTCOME_LOST = 'Lost';

    public static final String TIER_EXECUTIVE = 'Tier 2';

    public static final String STATUS_NOT_REQUIRED = 'Not Required';
    public static final String STATUS_NOT_SUBMITTED = 'Not Submitted';
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REJECTED = 'Rejected';

    public static final String ERROR_INVALID_INPUT = 'INVALID_INPUT';
    public static final String ERROR_NOT_FOUND = 'NOT_FOUND';
    public static final String ERROR_DML = 'DML_ERROR';

    private static final String PRIMARY_CONTACT_ROLE = 'Decision Maker';

    /** @description Approval tiers ordered by threshold, highest first. */
    @TestVisible
    private static List<Discount_Approval_Tier__mdt> approvalTiers {
        get {
            if (approvalTiers == null) {
                approvalTiers = sortTiersDescending(Discount_Approval_Tier__mdt.getAll().values());
            }
            return approvalTiers;
        }
        set {
            approvalTiers = value == null ? null : sortTiersDescending(value);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Trigger entry points (before insert / before update)
    // ---------------------------------------------------------------------------------------------

    /**
     * @description Derives Approval_Tier__c, Discount_Approval_Status__c and Executive_Approver__c
     * whenever the discount (or owner) changes. Lowering an approved discount keeps the approval;
     * raising it requires resubmission.
     */
    public static void applyDiscountApprovalPolicy(List<Opportunity> opps, Map<Id, Opportunity> oldMap) {
        List<Opportunity> needsExecutiveApprover = new List<Opportunity>();

        for (Opportunity opp : opps) {
            Opportunity oldOpp = oldMap == null ? null : oldMap.get(opp.Id);
            Decimal discount = opp.Discount_Percentage__c;

            if (discount != null && (discount < 0 || discount > 100)) {
                opp.Discount_Percentage__c.addError('Discount must be between 0% and 100%.');
                continue;
            }

            Boolean discountChanged = oldOpp == null || oldOpp.Discount_Percentage__c != discount;
            Boolean ownerChanged = oldOpp != null && oldOpp.OwnerId != opp.OwnerId;
            if (!discountChanged && !ownerChanged) {
                continue;
            }

            if (discountChanged) {
                if (oldOpp != null && oldOpp.Discount_Approval_Status__c == STATUS_PENDING) {
                    opp.Discount_Percentage__c.addError(
                        'Discount cannot change while approval is pending. Recall the approval request first.'
                    );
                    continue;
                }
                String tier = resolveTier(discount);
                opp.Approval_Tier__c = tier;
                opp.Discount_Approval_Status__c = resolveApprovalStatus(tier, oldOpp, discount);
            }

            if (opp.Approval_Tier__c == TIER_EXECUTIVE) {
                needsExecutiveApprover.add(opp);
            } else {
                opp.Executive_Approver__c = null;
            }
        }

        assignExecutiveApprovers(needsExecutiveApprover);
    }

    /**
     * @description Stage gates:
     *  - Closed Won: account not on credit hold, discount approval satisfied, and (on update)
     *    a primary contact role exists. Contact roles cannot exist before insert, so records
     *    created directly as Closed Won (data migration) skip that one check.
     *  - Closed Lost: a loss reason is required.
     */
    public static void validateStageProgression(List<Opportunity> newOpps, Map<Id, Opportunity> oldOppMap) {
        List<Opportunity> closingWon = new List<Opportunity>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> existingOppIds = new Set<Id>();

        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldOppMap == null ? null : oldOppMap.get(opp.Id);
            if (isTransitioningTo(opp, oldOpp, STAGE_CLOSED_LOST) && String.isBlank(opp.Loss_Reason__c)) {
                opp.Loss_Reason__c.addError('A Loss Reason is required to close an opportunity as lost.');
            }
            if (!isTransitioningTo(opp, oldOpp, STAGE_CLOSED_WON)) {
                continue;
            }
            closingWon.add(opp);
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
            if (opp.Id != null) {
                existingOppIds.add(opp.Id);
            }
        }

        if (closingWon.isEmpty()) {
            return;
        }

        Map<Id, Account> accounts = AccountsSelector.selectByIdWithCreditStatus(accountIds);
        Map<Id, Opportunity> detailedOpps = new Map<Id, Opportunity>(
            OpportunitiesSelector.selectByIdWithDetails(existingOppIds)
        );

        // Only one record-level error survives per record, so all gate violations are reported together.
        for (Opportunity opp : closingWon) {
            List<String> violations = new List<String>();
            Account acc = accounts.get(opp.AccountId);
            if (acc != null && acc.Credit_Hold__c) {
                violations.add('Cannot Close/Win an Opportunity when parent Account has an active Credit Hold.');
            }

            if (!isDiscountApprovalSatisfied(opp)) {
                violations.add(
                    'Cannot Close/Win an Opportunity until its ' + opp.Discount_Percentage__c + '% discount receives ' +
                    opp.Approval_Tier__c + ' approval (current status: ' + opp.Discount_Approval_Status__c + ').'
                );
            }

            Opportunity details = detailedOpps.get(opp.Id);
            if (details != null && !hasPrimaryContactRole(details)) {
                violations.add('Cannot Close/Win an Opportunity without a Primary Contact Role assigned.');
            }

            if (!violations.isEmpty()) {
                opp.addError(String.join(violations, ' '));
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Invocable orchestration (CloseOpportunityAction)
    // ---------------------------------------------------------------------------------------------

    /**
     * @description Closes opportunities as Won (optionally assigning a primary contact role) or Lost.
     * Bulk-safe with partial success: each request receives its own result envelope. Stage-gate
     * failures raised by the trigger come back as DML_ERROR with the validation message.
     */
    public static List<CloseOpportunityAction.Result> closeDeals(List<CloseOpportunityAction.Request> requests) {
        List<CloseOpportunityAction.Result> results = new List<CloseOpportunityAction.Result>();
        Map<Id, Integer> requestIndexByOppId = new Map<Id, Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            CloseOpportunityAction.Request req = requests[i];
            results.add(new CloseOpportunityAction.Result());
            String inputError = validateCloseRequest(req, requestIndexByOppId);
            if (inputError != null) {
                fail(results[i], ERROR_INVALID_INPUT, inputError, req.opportunityId);
                continue;
            }
            requestIndexByOppId.put(req.opportunityId, i);
        }

        Map<Id, Opportunity> oppsById = new Map<Id, Opportunity>(
            OpportunitiesSelector.selectByIdWithDetails(requestIndexByOppId.keySet())
        );
        for (Id oppId : new List<Id>(requestIndexByOppId.keySet())) {
            if (!oppsById.containsKey(oppId)) {
                fail(results[requestIndexByOppId.remove(oppId)], ERROR_NOT_FOUND, 'Opportunity not found or not accessible.', oppId);
            }
        }

        assignPrimaryContacts(requests, results, requestIndexByOppId, oppsById);

        List<Opportunity> oppUpdates = new List<Opportunity>();
        List<Integer> updateIndexes = new List<Integer>();
        for (Integer i : requestIndexByOppId.values()) {
            CloseOpportunityAction.Request req = requests[i];
            Opportunity opp = new Opportunity(Id = req.opportunityId);
            if (req.outcome == OUTCOME_WON) {
                opp.StageName = STAGE_CLOSED_WON;
            } else {
                opp.StageName = STAGE_CLOSED_LOST;
                opp.Loss_Reason__c = req.lossReason;
            }
            oppUpdates.add(opp);
            updateIndexes.add(i);
        }

        List<Database.SaveResult> saveResults = Database.update(oppUpdates, false, AccessLevel.USER_MODE);
        for (Integer j = 0; j < saveResults.size(); j++) {
            Integer i = updateIndexes[j];
            if (saveResults[j].isSuccess()) {
                results[i].isSuccess = true;
                results[i].payload = new CloseOpportunityAction.OutputPayload();
                results[i].payload.opportunityId = oppUpdates[j].Id;
                results[i].payload.stageName = oppUpdates[j].StageName;
            } else {
                fail(results[i], ERROR_DML, joinErrors(saveResults[j].getErrors()), oppUpdates[j].Id);
            }
        }

        if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
        return results;
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    @TestVisible
    private static String resolveTier(Decimal discount) {
        if (discount == null) {
            return null;
        }
        for (Discount_Approval_Tier__mdt tier : approvalTiers) {
            if (discount > tier.Discount_Threshold__c) {
                return tier.Approval_Tier__c;
            }
        }
        return null;
    }

    private static String resolveApprovalStatus(String tier, Opportunity oldOpp, Decimal discount) {
        if (tier == null) {
            return STATUS_NOT_REQUIRED;
        }
        Boolean wasApproved = oldOpp != null && oldOpp.Discount_Approval_Status__c == STATUS_APPROVED;
        if (wasApproved && oldOpp.Discount_Percentage__c != null && discount <= oldOpp.Discount_Percentage__c) {
            return STATUS_APPROVED;
        }
        return STATUS_NOT_SUBMITTED;
    }

    private static void assignExecutiveApprovers(List<Opportunity> opps) {
        if (opps.isEmpty()) {
            return;
        }
        Set<Id> ownerIds = new Set<Id>();
        for (Opportunity opp : opps) {
            ownerIds.add(opp.OwnerId == null ? UserInfo.getUserId() : opp.OwnerId);
        }
        Map<Id, User> owners = UsersSelector.selectByIdWithManagerChain(ownerIds);
        for (Opportunity opp : opps) {
            User owner = owners.get(opp.OwnerId == null ? UserInfo.getUserId() : opp.OwnerId);
            opp.Executive_Approver__c = owner == null ? null : resolveExecutiveApprover(owner);
        }
    }

    /** @description Owner's manager's manager when active; otherwise the owner's active manager. */
    private static Id resolveExecutiveApprover(User owner) {
        if (owner.Manager == null || owner.ManagerId == null) {
            return null;
        }
        if (owner.Manager.ManagerId != null && owner.Manager.Manager.IsActive) {
            return owner.Manager.ManagerId;
        }
        return owner.Manager.IsActive ? owner.ManagerId : null;
    }

    private static Boolean isTransitioningTo(Opportunity opp, Opportunity oldOpp, String stage) {
        return opp.StageName == stage && (oldOpp == null || oldOpp.StageName != stage);
    }

    private static Boolean isDiscountApprovalSatisfied(Opportunity opp) {
        return opp.Approval_Tier__c == null || opp.Discount_Approval_Status__c == STATUS_APPROVED;
    }

    private static Boolean hasPrimaryContactRole(Opportunity details) {
        for (OpportunityContactRole ocr : details.OpportunityContactRoles) {
            if (ocr.IsPrimary) {
                return true;
            }
        }
        return false;
    }

    private static String validateCloseRequest(CloseOpportunityAction.Request req, Map<Id, Integer> seen) {
        if (req.opportunityId == null) {
            return 'Opportunity Id is required.';
        }
        if (req.opportunityId.getSObjectType() != Opportunity.SObjectType) {
            return 'Opportunity Id does not reference an Opportunity.';
        }
        if (seen.containsKey(req.opportunityId)) {
            return 'Duplicate request for the same Opportunity in one batch.';
        }
        if (req.outcome != OUTCOME_WON && req.outcome != OUTCOME_LOST) {
            return 'Outcome must be "' + OUTCOME_WON + '" or "' + OUTCOME_LOST + '".';
        }
        if (req.outcome == OUTCOME_LOST && String.isBlank(req.lossReason)) {
            return 'A Loss Reason is required to close an opportunity as lost.';
        }
        if (String.isNotBlank(req.primaryContactId)) {
            try {
                if (Id.valueOf(req.primaryContactId).getSObjectType() != Contact.SObjectType) {
                    return 'Primary Contact Id does not reference a Contact.';
                }
            } catch (StringException ex) {
                return 'Primary Contact Id is not a valid record Id.';
            }
        }
        return null;
    }

    private static Id toContactId(String value) {
        return String.isBlank(value) ? null : Id.valueOf(value);
    }

    /**
     * @description Ensures the requested contact is the primary contact role for Won requests.
     * Requests whose contact role DML fails are marked failed and removed from requestIndexByOppId.
     */
    private static void assignPrimaryContacts(
        List<CloseOpportunityAction.Request> requests,
        List<CloseOpportunityAction.Result> results,
        Map<Id, Integer> requestIndexByOppId,
        Map<Id, Opportunity> oppsById
    ) {
        List<OpportunityContactRole> rolesToUpsert = new List<OpportunityContactRole>();
        List<Integer> roleIndexes = new List<Integer>();

        for (Integer i : requestIndexByOppId.values()) {
            CloseOpportunityAction.Request req = requests[i];
            Id contactId = toContactId(req.primaryContactId);
            if (req.outcome != OUTCOME_WON || contactId == null) {
                continue;
            }
            OpportunityContactRole existing = null;
            for (OpportunityContactRole ocr : oppsById.get(req.opportunityId).OpportunityContactRoles) {
                if (ocr.ContactId == contactId) {
                    existing = ocr;
                    break;
                }
            }
            if (existing != null && existing.IsPrimary) {
                continue;
            }
            rolesToUpsert.add(
                existing != null
                    ? new OpportunityContactRole(Id = existing.Id, IsPrimary = true)
                    : new OpportunityContactRole(
                          OpportunityId = req.opportunityId,
                          ContactId = contactId,
                          Role = PRIMARY_CONTACT_ROLE,
                          IsPrimary = true
                      )
            );
            roleIndexes.add(i);
        }

        if (rolesToUpsert.isEmpty()) {
            return;
        }
        List<Database.UpsertResult> upsertResults = Database.upsert(rolesToUpsert, false, AccessLevel.USER_MODE);
        for (Integer j = 0; j < upsertResults.size(); j++) {
            if (!upsertResults[j].isSuccess()) {
                Integer i = roleIndexes[j];
                Id oppId = requests[i].opportunityId;
                fail(results[i], ERROR_DML, 'Could not assign primary contact: ' + joinErrors(upsertResults[j].getErrors()), oppId);
                requestIndexByOppId.remove(oppId);
            }
        }
    }

    private static void fail(CloseOpportunityAction.Result result, String code, String message, Id recordId) {
        result.isSuccess = false;
        result.errorCode = code;
        result.errorMessage = message;
        Logger.error('CloseOpportunityAction ' + code + ': ' + message, recordId);
    }

    private static String joinErrors(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error err : errors) {
            messages.add(err.getMessage());
        }
        return String.join(messages, ' ');
    }

    private static List<Discount_Approval_Tier__mdt> sortTiersDescending(List<Discount_Approval_Tier__mdt> tiers) {
        List<TierComparable> sortable = new List<TierComparable>();
        for (Discount_Approval_Tier__mdt tier : tiers) {
            sortable.add(new TierComparable(tier));
        }
        sortable.sort();
        List<Discount_Approval_Tier__mdt> sorted = new List<Discount_Approval_Tier__mdt>();
        for (TierComparable item : sortable) {
            sorted.add(item.tier);
        }
        return sorted;
    }

    private class TierComparable implements Comparable {
        private Discount_Approval_Tier__mdt tier;

        private TierComparable(Discount_Approval_Tier__mdt tier) {
            this.tier = tier;
        }

        public Integer compareTo(Object other) {
            Decimal mine = tier.Discount_Threshold__c;
            Decimal theirs = ((TierComparable) other).tier.Discount_Threshold__c;
            return mine == theirs ? 0 : (mine > theirs ? -1 : 1);
        }
    }
}
