/**
 * @description User queries used to resolve approval chains. All queries run WITH USER_MODE.
 */
public virtual with sharing class UsersSelector {
    @TestVisible
    private static UsersSelector instance;

    /** @description Returns the selector; tests replace it with a Test.createStub() mock via `instance`. */
    public static UsersSelector newInstance() {
        if (instance == null) {
            instance = new UsersSelector();
        }
        return instance;
    }

    public virtual Map<Id, User> selectByIdWithManagerChain(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>(
            [
                SELECT Id, ManagerId, Manager.IsActive, Manager.ManagerId, Manager.Manager.IsActive
                FROM User
                WHERE Id IN :userIds
                WITH USER_MODE
            ]
        );
    }
}
