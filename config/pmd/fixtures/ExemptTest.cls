@IsTest
private class ExemptTest {
    @IsTest
    static void testCodeMayQueryInline() {
        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
    }
}
