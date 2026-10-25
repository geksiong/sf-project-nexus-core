/**
 * @description User queries used to resolve approval chains. All queries run WITH USER_MODE.
 */
public with sharing class UsersSelector {
    public static Map<Id, User> selectByIdWithManagerChain(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>([
            SELECT Id, ManagerId, Manager.IsActive, Manager.ManagerId, Manager.Manager.IsActive
            FROM User
            WHERE Id IN :userIds
            WITH USER_MODE
        ]);
    }
}
