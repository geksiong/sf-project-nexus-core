@IsTest
private class TriggerHandlerTest {
    private static String lastMethodCalled;

    private class TestHandler extends TriggerHandler {
        protected override void beforeInsert(List<SObject> newRecords) {
            lastMethodCalled = 'beforeInsert';
        }
        protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
            lastMethodCalled = 'beforeUpdate';
        }
        protected override void beforeDelete(List<SObject> deletedRecords, Map<Id, SObject> oldRecordMap) {
            lastMethodCalled = 'beforeDelete';
        }
        protected override void afterInsert(List<SObject> newRecords, Map<Id, SObject> newRecordMap) {
            lastMethodCalled = 'afterInsert';
        }
        protected override void afterUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
            lastMethodCalled = 'afterUpdate';
        }
        protected override void afterDelete(List<SObject> deletedRecords, Map<Id, SObject> oldRecordMap) {
            lastMethodCalled = 'afterDelete';
        }
        protected override void afterUndelete(List<SObject> restoredRecords, Map<Id, SObject> newRecordMap) {
            lastMethodCalled = 'afterUndelete';
        }
    }

    private static TestHandler buildHandler(System.TriggerOperation context) {
        TestHandler handler = new TestHandler();
        handler.isTriggerExecuting = true;
        handler.context = context;
        handler.newRecords = new List<Account>{ new Account(Name = 'Routing Test') };
        handler.oldRecords = handler.newRecords;
        return handler;
    }

    @IsTest
    static void routesEveryContextToMatchingMethod() {
        Map<System.TriggerOperation, String> expected = new Map<System.TriggerOperation, String>{
            System.TriggerOperation.BEFORE_INSERT => 'beforeInsert',
            System.TriggerOperation.BEFORE_UPDATE => 'beforeUpdate',
            System.TriggerOperation.BEFORE_DELETE => 'beforeDelete',
            System.TriggerOperation.AFTER_INSERT => 'afterInsert',
            System.TriggerOperation.AFTER_UPDATE => 'afterUpdate',
            System.TriggerOperation.AFTER_DELETE => 'afterDelete',
            System.TriggerOperation.AFTER_UNDELETE => 'afterUndelete'
        };
        for (System.TriggerOperation context : expected.keySet()) {
            lastMethodCalled = null;
            buildHandler(context).run();
            Assert.areEqual(expected.get(context), lastMethodCalled, 'Wrong route for ' + context);
        }
    }

    @IsTest
    static void baseClassDefaultsAreNoOps() {
        for (System.TriggerOperation context : System.TriggerOperation.values()) {
            TriggerHandler handler = new TriggerHandler();
            handler.isTriggerExecuting = true;
            handler.context = context;
            handler.run();
        }
        Assert.isNull(lastMethodCalled, 'Base handler must not invoke subclass logic');
    }

    @IsTest
    static void throwsOutsideTriggerContext() {
        try {
            new TestHandler().run();
            Assert.fail('Expected TriggerHandlerException');
        } catch (TriggerHandler.TriggerHandlerException ex) {
            Assert.isTrue(ex.getMessage().contains('outside of trigger execution'));
        }
    }

    @IsTest
    static void handlerBypassSkipsExecution() {
        TriggerHandler.bypass('TestHandler');
        Assert.isTrue(TriggerHandler.isBypassed('TestHandler'));
        buildHandler(System.TriggerOperation.BEFORE_INSERT).run();
        Assert.isNull(lastMethodCalled, 'Bypassed handler must not run');

        TriggerHandler.clearBypass('TestHandler');
        buildHandler(System.TriggerOperation.BEFORE_INSERT).run();
        Assert.areEqual('beforeInsert', lastMethodCalled);

        TriggerHandler.bypass('TestHandler');
        TriggerHandler.clearAllBypasses();
        Assert.isFalse(TriggerHandler.isBypassed('TestHandler'));
    }

    @IsTest
    static void objectBypassSkipsExecution() {
        BypassService.setTriggerBypass('Account', true);
        buildHandler(System.TriggerOperation.BEFORE_INSERT).run();
        Assert.isNull(lastMethodCalled, 'Object-level bypass must skip handler');
    }

    @IsTest
    static void maxLoopCountStopsRecursion() {
        TestHandler handler = buildHandler(System.TriggerOperation.AFTER_UPDATE);
        handler.setMaxLoopCount(1);

        handler.run();
        Assert.areEqual('afterUpdate', lastMethodCalled, 'First run is within the limit');

        lastMethodCalled = null;
        handler.run();
        Assert.isNull(lastMethodCalled, 'Second run exceeds the limit and is skipped');

        handler.setMaxLoopCount(5);
        handler.run();
        Assert.areEqual('afterUpdate', lastMethodCalled, 'Raised limit allows execution again');

        lastMethodCalled = null;
        handler.clearMaxLoopCount();
        handler.run();
        Assert.areEqual('afterUpdate', lastMethodCalled, 'Cleared limit allows execution');
    }

    @IsTest
    static void resolvesSObjectNameFromOldRecordsWhenNewIsEmpty() {
        TestHandler handler = buildHandler(System.TriggerOperation.AFTER_DELETE);
        handler.newRecords = null;
        BypassService.setTriggerBypass('Account', true);
        handler.run();
        Assert.isNull(lastMethodCalled, 'Delete context resolves SObject name from Trigger.old');
    }
}
