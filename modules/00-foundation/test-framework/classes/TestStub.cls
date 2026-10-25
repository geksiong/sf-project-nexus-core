/**
 * @description Generic System.StubProvider for in-memory unit tests. Returns canned responses per
 * method name and records every call, so services can be tested without SOQL or DML.
 *
 * Usage:
 *   TestStub facts = new TestStub().returns('selectAccountIdsOnCreditHold', new Set<Id>{ accountId });
 *   SalesEngineFactsSelector.instance = (SalesEngineFactsSelector) facts.create(SalesEngineFactsSelector.class);
 *   ...
 *   Assert.areEqual(1, facts.callCount('selectAccountIdsOnCreditHold'));
 */
@IsTest
public class TestStub implements System.StubProvider {
    private final Map<String, Object> responses = new Map<String, Object>();
    private final Map<String, List<List<Object>>> calls = new Map<String, List<List<Object>>>();

    public TestStub returns(String methodName, Object response) {
        responses.put(methodName.toLowerCase(), response);
        return this;
    }

    public Object create(Type stubbedType) {
        return Test.createStub(stubbedType, this);
    }

    public Integer callCount(String methodName) {
        List<List<Object>> methodCalls = calls.get(methodName.toLowerCase());
        return methodCalls == null ? 0 : methodCalls.size();
    }

    /** @description Arguments of the most recent call to the method, or null if it was never called. */
    public List<Object> lastArguments(String methodName) {
        List<List<Object>> methodCalls = calls.get(methodName.toLowerCase());
        return methodCalls == null ? null : methodCalls[methodCalls.size() - 1];
    }

    public Object handleMethodCall(
        Object stubbedObject,
        String stubbedMethodName,
        Type returnType,
        List<Type> listOfParamTypes,
        List<String> listOfParamNames,
        List<Object> listOfArgs
    ) {
        String key = stubbedMethodName.toLowerCase();
        if (!calls.containsKey(key)) {
            calls.put(key, new List<List<Object>>());
        }
        calls.get(key).add(listOfArgs);
        return responses.get(key);
    }
}
