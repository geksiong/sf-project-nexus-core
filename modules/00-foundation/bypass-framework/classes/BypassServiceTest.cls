@IsTest
private class BypassServiceTest {
    @IsTest
    static void localBypassIsCaseInsensitiveAndClearable() {
        BypassService.hasBypassPermission = false;
        BypassService.settingsBySObject = new Map<String, Trigger_Setting__mdt>();

        Assert.isFalse(BypassService.isTriggerBypassed('Opportunity'));
        BypassService.setTriggerBypass('Opportunity', true);
        Assert.isTrue(BypassService.isTriggerBypassed('opportunity'));

        BypassService.setTriggerBypass('OPPORTUNITY', false);
        Assert.isFalse(BypassService.isTriggerBypassed('Opportunity'));

        BypassService.setTriggerBypass('Account', true);
        BypassService.clearAllBypasses();
        Assert.isFalse(BypassService.isTriggerBypassed('Account'));
    }

    @IsTest
    static void customMetadataKillSwitchDisablesTrigger() {
        BypassService.hasBypassPermission = false;
        BypassService.settingsBySObject = new Map<String, Trigger_Setting__mdt>{
            'case' => new Trigger_Setting__mdt(SObject_API_Name__c = 'Case', Is_Disabled__c = true),
            'account' => new Trigger_Setting__mdt(SObject_API_Name__c = 'Account', Is_Disabled__c = false)
        };
        Assert.isTrue(BypassService.isTriggerBypassed('Case'));
        Assert.isFalse(BypassService.isTriggerBypassed('Account'));
    }

    @IsTest
    static void customPermissionBypassesAllTriggers() {
        BypassService.settingsBySObject = new Map<String, Trigger_Setting__mdt>();
        BypassService.hasBypassPermission = true;
        Assert.isTrue(BypassService.isTriggerBypassed('Opportunity'));
    }

    @IsTest
    static void blankObjectNameIsNeverBypassed() {
        Assert.isFalse(BypassService.isTriggerBypassed(''));
        Assert.isFalse(BypassService.isTriggerBypassed(null));
    }

    @IsTest
    static void loadsDeployedSettingsLazily() {
        // Exercises the lazy getters against the deployed CMDT records and real permission check.
        Assert.isNotNull(BypassService.settingsBySObject);
        Assert.isNotNull(BypassService.hasBypassPermission);
    }
}
