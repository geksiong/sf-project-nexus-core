/**
 * @description Central trigger bypass orchestration. A trigger is bypassed when any of these apply:
 *  1. Transactional bypass set in Apex via setTriggerBypass() (e.g. bulk service operations).
 *  2. Org-wide kill switch: an active Trigger_Setting__mdt record with Is_Disabled__c = true.
 *  3. Running user holds the Bypass_Triggers custom permission (data migration users).
 */
public with sharing class BypassService {
    public static final String BYPASS_ALL_PERMISSION = 'Bypass_Triggers';

    private static Set<String> localBypasses = new Set<String>();

    @TestVisible
    private static Map<String, Trigger_Setting__mdt> settingsBySObject {
        get {
            if (settingsBySObject == null) {
                settingsBySObject = new Map<String, Trigger_Setting__mdt>();
                for (Trigger_Setting__mdt setting : Trigger_Setting__mdt.getAll().values()) {
                    settingsBySObject.put(setting.SObject_API_Name__c.toLowerCase(), setting);
                }
            }
            return settingsBySObject;
        }
        set;
    }

    @TestVisible
    private static Boolean hasBypassPermission {
        get {
            if (hasBypassPermission == null) {
                hasBypassPermission = FeatureManagement.checkPermission(BYPASS_ALL_PERMISSION);
            }
            return hasBypassPermission;
        }
        set;
    }

    public static Boolean isTriggerBypassed(String objectName) {
        if (String.isBlank(objectName)) {
            return false;
        }
        String key = objectName.toLowerCase();
        if (localBypasses.contains(key) || hasBypassPermission) {
            return true;
        }
        Trigger_Setting__mdt setting = settingsBySObject.get(key);
        return setting != null && setting.Is_Disabled__c;
    }

    public static void setTriggerBypass(String objectName, Boolean bypass) {
        if (bypass) {
            localBypasses.add(objectName.toLowerCase());
        } else {
            localBypasses.remove(objectName.toLowerCase());
        }
    }

    public static void clearAllBypasses() {
        localBypasses.clear();
    }
}
