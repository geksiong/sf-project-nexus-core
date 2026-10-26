/**
 * @description Partner Central test personas: a channel manager (Sales Manager role) who owns two partner
 * accounts, each with partner users. Partner (portal) roles are created under the account owner's role.
 */
@IsTest
public class PartnerTestFixtures {
    public static final String CHANNEL_MANAGER = 'NexusChannelManager';
    public static final String PARTNER_A_USER = 'NexusPartnerAUser';
    public static final String PARTNER_A_MANAGER = 'NexusPartnerAManager';
    public static final String PARTNER_B_USER = 'NexusPartnerBUser';
    public static final String PARTNER_PROFILE = 'Nexus Partner User';

    public static void createPartners() {
        User channelManager;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            channelManager = TestDataFactory.createTestUser('Standard User', 'Sales_Manager');
            channelManager.LastName = CHANNEL_MANAGER;
            insert channelManager;
            assign(channelManager.Id, 'PS_Channel_Manager');
            assign(channelManager.Id, 'PS_Sales_Rep');
        }
        List<Account> partners = new List<Account>{
            new Account(Name = 'Partner A Solutions', OwnerId = channelManager.Id),
            new Account(Name = 'Partner B Integrators', OwnerId = channelManager.Id)
        };
        insert partners;
        for (Account partner : partners) {
            partner.IsPartner = true;
        }
        update partners;
        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = PARTNER_A_USER, AccountId = partners[0].Id),
            new Contact(LastName = PARTNER_A_MANAGER, AccountId = partners[0].Id),
            new Contact(LastName = PARTNER_B_USER, AccountId = partners[1].Id)
        };
        insert contacts;

        Id profileId = [SELECT Id FROM Profile WHERE Name = :PARTNER_PROFILE].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> partnerUsers = new List<User>();
            for (Contact c : contacts) {
                User u = TestDataFactory.createTestUser('Standard User', null);
                u.ProfileId = profileId;
                u.ContactId = c.Id;
                u.LastName = c.LastName;
                partnerUsers.add(u);
            }
            insert partnerUsers;
            // The partner manager sits above partner users in the account's portal role hierarchy.
            Map<String, Id> portalRoles = new Map<String, Id>();
            for (UserRole role : [SELECT Id, PortalRole FROM UserRole WHERE PortalAccountId = :partners[0].Id]) {
                portalRoles.put(role.PortalRole, role.Id);
            }
            if (portalRoles.containsKey('Manager') && portalRoles.containsKey('Worker')) {
                update new List<User>{
                    new User(Id = partnerUsers[0].Id, UserRoleId = portalRoles.get('Worker')),
                    new User(Id = partnerUsers[1].Id, UserRoleId = portalRoles.get('Manager'))
                };
            }
            for (User u : partnerUsers) {
                assign(u.Id, 'PS_Partner_Deal_Registration');
            }
        }
    }

    private static void assign(Id userId, String permissionSet) {
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSet]
            .Id
        );
    }

    public static User getUser(String lastName) {
        return [SELECT Id, UserRoleId, UserRole.PortalRole FROM User WHERE LastName = :lastName LIMIT 1];
    }

    public static Account partner(String name) {
        return [SELECT Id, OwnerId FROM Account WHERE Name = :name AND IsPartner = TRUE];
    }

    public static SubmitDealRegistrationAction.Request request(String company, Decimal amount) {
        SubmitDealRegistrationAction.Request req = new SubmitDealRegistrationAction.Request();
        req.customerCompany = company;
        req.customerContactName = 'Pat Buyer';
        req.customerEmail = 'pat@example.com';
        req.estimatedAmount = amount;
        req.expectedCloseDate = Date.today().addDays(45);
        req.productInterest = 'Field Service';
        return req;
    }
}
