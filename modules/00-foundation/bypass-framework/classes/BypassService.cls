public with sharing class BypassService {
    private static Set<String> localBypasses = new Set<String>();

    public static Boolean isTriggerBypassed(String objectName) {
        if (localBypasses.contains(objectName.toLowerCase())) {
            return true;
        }
        return false;
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