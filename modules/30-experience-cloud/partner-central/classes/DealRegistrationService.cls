/**
 * @description Partner deal registration (Demo App 6, Nexus Partner Central).
 *
 *  prepareRegistrations (before insert)  partner account from the partner user's contact, channel manager =
 *                                        partner account owner, Status = Submitted, channel conflict check:
 *                                        one open registration per customer across all partners.
 *  submitForApproval    (after insert)   submits each registration to the Deal Registration Approval process
 *                                        (routed to Channel_Manager__c).
 *  convertApproved      (before update)  on approval: reuses or creates the customer account and creates the
 *                                        opportunity (owned by the channel manager), linked in Opportunity__c.
 *  submitRegistrations  (invocable)      Partner_Deal_Registration flow / Agentforce: user-mode insert, so only
 *                                        users with PS_Partner_Deal_Registration can register.
 *
 * Partners cannot see other partners' registrations, their channel manager or existing customer accounts, so
 * the rules read through DealRegistrationFactsSelector (system mode). Conversion writes in system mode: it is the
 * consequence of an approval the channel manager was entitled to give.
 */
public with sharing class DealRegistrationService {
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_APPROVED = 'Approved';
    public static final Set<String> OPEN_STATUSES = new Set<String>{ STATUS_SUBMITTED, STATUS_APPROVED };
    public static final String CONFLICT_PREFIX = 'Channel conflict: ';
    public static final String LEAD_SOURCE = 'Partner Referral';
    public static final String OPPORTUNITY_STAGE = 'Prospecting';

    public static final String ERROR_INVALID_INPUT = 'INVALID_INPUT';
    public static final String ERROR_CHANNEL_CONFLICT = 'CHANNEL_CONFLICT';
    public static final String ERROR_DML = 'DML_ERROR';

    private static final Set<StatusCode> EXPECTED_REJECTION_CODES = new Set<StatusCode>{
        StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
        StatusCode.INSUFFICIENT_ACCESS_OR_READONLY,
        StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY,
        StatusCode.REQUIRED_FIELD_MISSING
    };

    /** @description Case- and whitespace-insensitive customer key for the channel conflict rule. */
    public static String companyKey(String companyName) {
        return companyName == null ? null : companyName.trim().replaceAll('\\s+', ' ').toLowerCase();
    }

    // ---------------------------------------------------------------------------------------------
    // Trigger entry points
    // ---------------------------------------------------------------------------------------------

    public static void prepareRegistrations(List<Deal_Registration__c> registrations) {
        DealRegistrationFactsSelector facts = DealRegistrationFactsSelector.newInstance();
        Set<Id> ownerIds = new Set<Id>();
        for (Deal_Registration__c reg : registrations) {
            ownerIds.add(reg.OwnerId == null ? UserInfo.getUserId() : reg.OwnerId);
        }
        Map<Id, Id> partnerOfUser = facts.selectPartnerAccountIds(ownerIds);

        Set<Id> partnerAccountIds = new Set<Id>();
        Set<String> companyKeys = new Set<String>();
        for (Deal_Registration__c reg : registrations) {
            reg.Status__c = STATUS_SUBMITTED;
            if (reg.Customer_Company__c != null) {
                reg.Customer_Company__c = reg.Customer_Company__c.trim().replaceAll('\\s+', ' ');
                companyKeys.add(companyKey(reg.Customer_Company__c));
            }
            if (reg.Partner_Account__c == null) {
                reg.Partner_Account__c = partnerOfUser.get(reg.OwnerId == null ? UserInfo.getUserId() : reg.OwnerId);
            }
            if (reg.Partner_Account__c == null) {
                reg.Partner_Account__c.addError(
                    'Deal registrations must come from a partner user or name a partner account.'
                );
            } else {
                partnerAccountIds.add(reg.Partner_Account__c);
            }
        }

        Map<Id, Id> channelManagers = facts.selectChannelManagerIds(partnerAccountIds);
        Map<String, Id> openRegistrations = facts.selectOpenRegistrationPartners(companyKeys, null);
        for (Deal_Registration__c reg : registrations) {
            if (reg.Partner_Account__c == null) {
                continue;
            }
            reg.Channel_Manager__c = channelManagers.get(reg.Partner_Account__c);
            if (reg.Channel_Manager__c == null) {
                reg.addError('The partner account has no active channel manager to approve the registration.');
                continue;
            }
            String key = companyKey(reg.Customer_Company__c);
            if (key == null) {
                continue;
            }
            if (openRegistrations.containsKey(key)) {
                // Names neither the other partner nor the registration: only that the customer is taken.
                reg.addError(
                    CONFLICT_PREFIX +
                    (openRegistrations.get(key) == reg.Partner_Account__c
                        ? 'your organisation already has an open registration for ' + reg.Customer_Company__c + '.'
                        : reg.Customer_Company__c + ' is already registered by another partner.')
                );
            } else {
                openRegistrations.put(key, reg.Partner_Account__c);
            }
        }
    }

    public static void submitForApproval(List<Deal_Registration__c> registrations) {
        List<Approval.ProcessSubmitRequest> submissions = new List<Approval.ProcessSubmitRequest>();
        for (Deal_Registration__c reg : registrations) {
            Approval.ProcessSubmitRequest submission = new Approval.ProcessSubmitRequest();
            submission.setObjectId(reg.Id);
            submission.setSubmitterId(reg.OwnerId);
            submission.setComments('Partner deal registration for ' + reg.Customer_Company__c);
            submissions.add(submission);
        }
        for (Approval.ProcessResult result : Approval.process(submissions, false)) {
            if (!result.isSuccess()) {
                Logger.error(
                    'Deal registration could not be submitted for approval: ' + result.getErrors()[0].getMessage(),
                    result.getEntityId()
                );
            }
        }
        if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
    }

    public static void convertApproved(List<Deal_Registration__c> registrations, Map<Id, Deal_Registration__c> oldMap) {
        List<Deal_Registration__c> approved = new List<Deal_Registration__c>();
        Set<String> companyKeys = new Set<String>();
        for (Deal_Registration__c reg : registrations) {
            Deal_Registration__c old = oldMap.get(reg.Id);
            if (reg.Status__c == STATUS_APPROVED && old.Status__c != STATUS_APPROVED && reg.Opportunity__c == null) {
                approved.add(reg);
                companyKeys.add(companyKey(reg.Customer_Company__c));
            }
        }
        if (approved.isEmpty()) {
            return;
        }

        Map<String, Id> accountIds = DealRegistrationFactsSelector.newInstance().selectAccountIdsByName(companyKeys);
        Map<String, Account> newAccounts = new Map<String, Account>();
        for (Deal_Registration__c reg : approved) {
            String key = companyKey(reg.Customer_Company__c);
            if (!accountIds.containsKey(key) && !newAccounts.containsKey(key)) {
                newAccounts.put(key, new Account(Name = reg.Customer_Company__c, OwnerId = reg.Channel_Manager__c));
            }
        }
        if (!newAccounts.isEmpty()) {
            List<String> keys = new List<String>(newAccounts.keySet());
            List<Database.SaveResult> results = Database.insert(newAccounts.values(), false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    accountIds.put(keys[i], results[i].getId());
                }
            }
        }

        List<Opportunity> opportunities = new List<Opportunity>();
        List<Deal_Registration__c> converting = new List<Deal_Registration__c>();
        for (Deal_Registration__c reg : approved) {
            Id accountId = accountIds.get(companyKey(reg.Customer_Company__c));
            if (accountId == null) {
                reg.addError('The customer account could not be created, so the registration was not approved.');
                continue;
            }
            opportunities.add(
                new Opportunity(
                    Name = (reg.Customer_Company__c +
                        ' - ' +
                        (reg.Product_Interest__c ?? 'Partner deal'))
                        .abbreviate(120),
                    AccountId = accountId,
                    OwnerId = reg.Channel_Manager__c,
                    StageName = OPPORTUNITY_STAGE,
                    CloseDate = reg.Expected_Close_Date__c,
                    Amount = reg.Estimated_Amount__c,
                    LeadSource = LEAD_SOURCE,
                    Description = 'Registered by partner through Nexus Partner Central (' + reg.Name + ').'
                )
            );
            converting.add(reg);
        }
        List<Database.SaveResult> results = Database.insert(opportunities, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                converting[i].Opportunity__c = results[i].getId();
            } else {
                // Fails the approval: the channel manager sees why and can retry.
                converting[i]
                    .addError('The opportunity could not be created: ' + results[i].getErrors()[0].getMessage());
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Invocable orchestration (SubmitDealRegistrationAction)
    // ---------------------------------------------------------------------------------------------

    public static List<SubmitDealRegistrationAction.Result> submitRegistrations(
        List<SubmitDealRegistrationAction.Request> requests
    ) {
        List<SubmitDealRegistrationAction.Result> results = new List<SubmitDealRegistrationAction.Result>();
        List<Deal_Registration__c> registrations = new List<Deal_Registration__c>();
        List<Integer> indexes = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            results.add(new SubmitDealRegistrationAction.Result());
            SubmitDealRegistrationAction.Request req = requests[i];
            String inputError = validate(req);
            if (inputError != null) {
                fail(results[i], ERROR_INVALID_INPUT, inputError, true);
                continue;
            }
            registrations.add(
                new Deal_Registration__c(
                    Customer_Company__c = req.customerCompany,
                    Customer_Contact_Name__c = req.customerContactName,
                    Customer_Email__c = req.customerEmail,
                    Estimated_Amount__c = req.estimatedAmount,
                    Expected_Close_Date__c = req.expectedCloseDate,
                    Product_Interest__c = String.isBlank(req.productInterest) ? null : req.productInterest
                )
            );
            indexes.add(i);
        }

        List<Database.SaveResult> saveResults = Database.insert(registrations, false, AccessLevel.USER_MODE);
        for (Integer j = 0; j < saveResults.size(); j++) {
            Integer i = indexes[j];
            if (saveResults[j].isSuccess()) {
                results[i].isSuccess = true;
                results[i].payload = new SubmitDealRegistrationAction.OutputPayload();
                results[i].payload.dealRegistrationId = saveResults[j].getId();
                results[i].payload.status = STATUS_SUBMITTED;
                continue;
            }
            List<String> messages = new List<String>();
            Boolean conflict = false;
            Boolean expected = true;
            for (Database.Error err : saveResults[j].getErrors()) {
                messages.add(err.getMessage());
                conflict |= err.getMessage().startsWith(CONFLICT_PREFIX);
                expected &= EXPECTED_REJECTION_CODES.contains(err.getStatusCode());
            }
            fail(results[i], conflict ? ERROR_CHANNEL_CONFLICT : ERROR_DML, String.join(messages, ' '), expected);
        }
        if (Logger.getBufferSize() > 0) {
            Logger.saveLog();
        }
        return results;
    }

    private static String validate(SubmitDealRegistrationAction.Request req) {
        if (String.isBlank(req.customerCompany)) {
            return 'Customer company is required.';
        }
        if (req.estimatedAmount == null || req.estimatedAmount <= 0) {
            return 'Estimated amount must be greater than zero.';
        }
        if (req.expectedCloseDate == null || req.expectedCloseDate < Date.today()) {
            return 'Expected close date must be today or later.';
        }
        if (String.isNotBlank(req.productInterest)) {
            for (
                Schema.PicklistEntry entry : Deal_Registration__c.Product_Interest__c.getDescribe().getPicklistValues()
            ) {
                if (entry.isActive() && entry.getValue() == req.productInterest) {
                    return null;
                }
            }
            return 'Unknown product interest "' + req.productInterest + '".';
        }
        return null;
    }

    private static void fail(
        SubmitDealRegistrationAction.Result result,
        String code,
        String message,
        Boolean isExpected
    ) {
        result.isSuccess = false;
        result.errorCode = code;
        result.errorMessage = message;
        String logMessage = 'SubmitDealRegistrationAction ' + code + ': ' + message;
        if (isExpected) {
            Logger.warn(logMessage);
        } else {
            Logger.error(logMessage);
        }
    }
}
