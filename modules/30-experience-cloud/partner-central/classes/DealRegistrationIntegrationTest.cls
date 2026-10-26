/**
 * @description Deal registration end to end with real partner users: submission from the portal, routing
 * and approval by the channel manager, conversion to an opportunity, channel conflicts between partners,
 * and Private OWD with the partner role hierarchy.
 */
@IsTest
private class DealRegistrationIntegrationTest {
    @TestSetup
    static void setup() {
        PartnerTestFixtures.createPartners();
    }

    private static SubmitDealRegistrationAction.Result submitAs(String lastName, String company, Decimal amount) {
        SubmitDealRegistrationAction.Result result;
        System.runAs(PartnerTestFixtures.getUser(lastName)) {
            result = SubmitDealRegistrationAction.execute(
                new List<SubmitDealRegistrationAction.Request>{ PartnerTestFixtures.request(company, amount) }
            )[0];
        }
        return result;
    }

    private static Deal_Registration__c reload(Id registrationId) {
        return [
            SELECT Id, Name, Status__c, OwnerId, Partner_Account__c, Channel_Manager__c, Opportunity__c
            FROM Deal_Registration__c
            WHERE Id = :registrationId
        ];
    }

    @IsTest
    static void partnerSubmissionRoutesToTheChannelManagerForApproval() {
        SubmitDealRegistrationAction.Result result = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Initech', 55000);

        Assert.isTrue(result.isSuccess, String.valueOf(result));
        Deal_Registration__c saved = reload(result.payload.dealRegistrationId);
        User manager = PartnerTestFixtures.getUser(PartnerTestFixtures.CHANNEL_MANAGER);
        Assert.areEqual(PartnerTestFixtures.partner('Partner A Solutions').Id, saved.Partner_Account__c);
        Assert.areEqual(manager.Id, saved.Channel_Manager__c);
        Assert.areEqual(PartnerTestFixtures.getUser(PartnerTestFixtures.PARTNER_A_USER).Id, saved.OwnerId);
        ProcessInstanceWorkitem workItem = [
            SELECT ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :saved.Id
        ];
        Assert.areEqual(manager.Id, workItem.ActorId, 'Routed to the channel manager');
    }

    @IsTest
    static void approvalCreatesTheCustomerAccountAndOpportunity() {
        Id registrationId = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Initech', 55000).payload.dealRegistrationId;
        User manager = PartnerTestFixtures.getUser(PartnerTestFixtures.CHANNEL_MANAGER);
        Id workItemId = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :registrationId]
        .Id;

        System.runAs(manager) {
            Approval.ProcessWorkitemRequest approve = new Approval.ProcessWorkitemRequest();
            approve.setWorkitemId(workItemId);
            approve.setAction('Approve');
            Approval.process(approve);
        }

        Deal_Registration__c saved = reload(registrationId);
        Assert.areEqual(DealRegistrationService.STATUS_APPROVED, saved.Status__c);
        Assert.isNotNull(saved.Opportunity__c);
        Opportunity opp = [
            SELECT Amount, OwnerId, LeadSource, StageName, Account.Name, Account.OwnerId
            FROM Opportunity
            WHERE Id = :saved.Opportunity__c
        ];
        Assert.areEqual(55000, opp.Amount);
        Assert.areEqual(manager.Id, opp.OwnerId);
        Assert.areEqual(DealRegistrationService.LEAD_SOURCE, opp.LeadSource);
        Assert.areEqual('Initech', opp.Account.Name);
        Assert.areEqual(manager.Id, opp.Account.OwnerId, 'New customer account is owned by the channel manager');
        Assert.areEqual(
            Date.today().addDays(DealRegistrationService.RESERVATION_DAYS),
            [SELECT Expires_On__c FROM Deal_Registration__c WHERE Id = :registrationId].Expires_On__c
        );

        // KI-035: the registering partner can follow the opportunity; other partners cannot.
        System.runAs(PartnerTestFixtures.getUser(PartnerTestFixtures.PARTNER_A_USER)) {
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Opportunity WHERE Id = :saved.Opportunity__c],
                'Registering partner'
            );
        }
        System.runAs(PartnerTestFixtures.getUser(PartnerTestFixtures.PARTNER_B_USER)) {
            Assert.areEqual(0, [SELECT COUNT() FROM Opportunity WHERE Id = :saved.Opportunity__c], 'Other partner');
        }
    }

    private static Id approve(Id registrationId) {
        Id workItemId = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :registrationId]
        .Id;
        System.runAs(PartnerTestFixtures.getUser(PartnerTestFixtures.CHANNEL_MANAGER)) {
            Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
            decision.setWorkitemId(workItemId);
            decision.setAction('Approve');
            Approval.process(decision);
        }
        return reload(registrationId).Opportunity__c;
    }

    /** @description KI-035: a reservation ends at Expires_On__c or when its opportunity closes. */
    @IsTest
    static void reservationsLapseAfterExpiryOrWhenTheOpportunityCloses() {
        Id expiring = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Initech', 1000).payload.dealRegistrationId;
        approve(expiring);
        Id closing = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Globex', 2000).payload.dealRegistrationId;
        Id closingOpportunity = approve(closing);
        Assert.areEqual(
            DealRegistrationService.ERROR_CHANNEL_CONFLICT,
            submitAs(PartnerTestFixtures.PARTNER_B_USER, 'Initech', 500).errorCode,
            'Approved and live: reserved'
        );

        update new Deal_Registration__c(Id = expiring, Expires_On__c = Date.today().addDays(-1));
        update new Opportunity(Id = closingOpportunity, StageName = 'Closed Lost', Loss_Reason__c = 'Price');

        Assert.isTrue(submitAs(PartnerTestFixtures.PARTNER_B_USER, 'Initech', 500).isSuccess, 'Expired: released');
        Assert.isTrue(submitAs(PartnerTestFixtures.PARTNER_B_USER, 'Globex', 500).isSuccess, 'Closed: released');

        Assert.areEqual(2, DealRegistrationService.releaseLapsedReservations());
        Assert.areEqual(DealRegistrationService.STATUS_EXPIRED, reload(expiring).Status__c);
        Assert.areEqual(DealRegistrationService.STATUS_CLOSED, reload(closing).Status__c);
    }

    @IsTest
    static void approvedRegistrationsRejectChangesEvenFromAdministrators() {
        Id registrationId = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Initech', 1000).payload.dealRegistrationId;
        approve(registrationId);
        try {
            update new Deal_Registration__c(Id = registrationId, Estimated_Amount__c = 5000000);
            Assert.fail('Approved registrations are frozen');
        } catch (DmlException ex) {
            Assert.isTrue(ex.getMessage().contains('cannot be changed'), ex.getMessage());
        }
    }

    @IsTest
    static void expiryJobRunsTheRelease() {
        Id registrationId = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Initech', 1000).payload.dealRegistrationId;
        approve(registrationId);
        update new Deal_Registration__c(Id = registrationId, Expires_On__c = Date.today().addDays(-1));

        Test.startTest();
        System.schedule('Test expiry', DealRegistrationExpiryJob.CRON_DAILY, new DealRegistrationExpiryJob());
        new DealRegistrationExpiryJob().execute(null);
        Test.stopTest();

        Assert.areEqual(DealRegistrationService.STATUS_EXPIRED, reload(registrationId).Status__c);
    }

    @IsTest
    static void anotherPartnerCannotRegisterTheSameCustomer() {
        Assert.isTrue(submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Initech', 55000).isSuccess);

        SubmitDealRegistrationAction.Result conflict = submitAs(PartnerTestFixtures.PARTNER_B_USER, ' initech ', 9000);

        Assert.isFalse(conflict.isSuccess);
        Assert.areEqual(DealRegistrationService.ERROR_CHANNEL_CONFLICT, conflict.errorCode, conflict.errorMessage);
        Assert.isTrue(conflict.errorMessage.contains('another partner'), conflict.errorMessage);
        Assert.isFalse(conflict.errorMessage.contains('Partner A'), 'The other partner is not disclosed');
    }

    /** @description A recalled registration is Withdrawn and stops reserving the customer. */
    @IsTest
    static void recalledRegistrationsReleaseTheCustomer() {
        Id registrationId = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Initech', 55000).payload.dealRegistrationId;
        Id workItemId = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :registrationId]
        .Id;

        System.runAs(PartnerTestFixtures.getUser(PartnerTestFixtures.PARTNER_A_USER)) {
            Approval.ProcessWorkitemRequest recall = new Approval.ProcessWorkitemRequest();
            recall.setWorkitemId(workItemId);
            recall.setAction('Removed');
            Approval.process(recall);
        }

        Assert.areEqual(DealRegistrationService.STATUS_WITHDRAWN, reload(registrationId).Status__c);
        SubmitDealRegistrationAction.Result other = submitAs(PartnerTestFixtures.PARTNER_B_USER, 'Initech', 9000);
        Assert.isTrue(other.isSuccess, 'A withdrawn registration no longer blocks other partners: ' + other);
    }

    @IsTest
    static void conversionNeverAttachesTheOpportunityToAPartnerAccount() {
        Id registrationId = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Partner B Integrators', 7000)
            .payload.dealRegistrationId;
        Id workItemId = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :registrationId]
        .Id;
        System.runAs(PartnerTestFixtures.getUser(PartnerTestFixtures.CHANNEL_MANAGER)) {
            Approval.ProcessWorkitemRequest approve = new Approval.ProcessWorkitemRequest();
            approve.setWorkitemId(workItemId);
            approve.setAction('Approve');
            Approval.process(approve);
        }

        Opportunity opp = [
            SELECT AccountId, Account.IsPartner
            FROM Opportunity
            WHERE Id = :reload(registrationId).Opportunity__c
        ];
        Assert.areNotEqual(PartnerTestFixtures.partner('Partner B Integrators').Id, opp.AccountId);
        Assert.isFalse(opp.Account.IsPartner, 'A new customer account is created instead');
    }

    /** @description Private OWD: partner managers see their team's registrations; other partners see nothing. */
    @IsTest
    static void partnerRoleHierarchyControlsVisibility() {
        Id registrationId = submitAs(PartnerTestFixtures.PARTNER_A_USER, 'Initech', 55000).payload.dealRegistrationId;

        User partnerManager = PartnerTestFixtures.getUser(PartnerTestFixtures.PARTNER_A_MANAGER);
        User worker = PartnerTestFixtures.getUser(PartnerTestFixtures.PARTNER_A_USER);
        Boolean hierarchyConfigured =
            partnerManager.UserRole?.PortalRole == 'Manager' &&
            worker.UserRole?.PortalRole == 'Worker';
        System.runAs(PartnerTestFixtures.getUser(PartnerTestFixtures.PARTNER_B_USER)) {
            Assert.areEqual(0, [SELECT COUNT() FROM Deal_Registration__c WHERE Id = :registrationId], 'Other partner');
        }
        if (hierarchyConfigured) {
            System.runAs(partnerManager) {
                Assert.areEqual(
                    1,
                    [SELECT COUNT() FROM Deal_Registration__c WHERE Id = :registrationId],
                    'Partner manager'
                );
            }
        }
        Assert.isTrue(hierarchyConfigured, 'Partner accounts get Manager and Worker portal roles');
    }

    @IsTest
    static void internalUsersWithoutAPartnerAccountCannotRegister() {
        SubmitDealRegistrationAction.Result result;
        System.runAs(PartnerTestFixtures.getUser(PartnerTestFixtures.CHANNEL_MANAGER)) {
            result = SubmitDealRegistrationAction.execute(
                new List<SubmitDealRegistrationAction.Request>{ PartnerTestFixtures.request('Hooli', 1000) }
            )[0];
        }
        Assert.isFalse(result.isSuccess);
        Assert.areEqual(DealRegistrationService.ERROR_DML, result.errorCode, String.valueOf(result));
    }
}
