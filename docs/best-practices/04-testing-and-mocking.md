# Nexus Core Engineering Standard: Testing & In-Memory Mocking

- **Standard Code:** `BP-TEST-004`
- **Module Target:** every `*Test.cls`; shared helpers in `modules/00-foundation/test-framework/`
- **Related ADR:** `docs/adr/0001-pragmatic-clean-architecture.md`

---

## 1. Test Pyramid

| Layer | What it proves | How | Example |
| --- | --- | --- | --- |
| **Unit (in-memory)** | Business rules in `*Service.cls` | Call the service directly with in-memory records; mock selectors with `TestStub`. No SOQL, no DML. | `OpportunityServiceTest` (17 tests, ~0.4s) |
| **Integration (DML)** | Trigger wiring, bulkification (200 records), bypass, record locking | Real DML through the trigger; keep the count small. | `OpportunityTriggerIntegrationTest` |
| **Platform contract** | Approval processes, permission sets, user-mode access, Nebula logging | Real users via `System.runAs`, real platform features. | `OpportunityDiscountApprovalTest`, `CloseOpportunityActionTest` |

Apex tests in a scratch org run serially, so total execution time is the sum of every test. Put each rule in the
cheapest layer that can prove it; the Phase 1 DoD budget was **< 15s**; with the Phase 3 service desk the whole suite runs in ~35s.

## 2. Mocking Selectors with `TestStub`

Selectors expose a `@TestVisible` static `instance` and a `newInstance()` factory, so services never construct them
directly. `TestStub` (`System.StubProvider`) returns canned responses and records calls:

```apex
TestStub facts = new TestStub()
    .returns('selectAccountIdsOnCreditHold', new Set<Id>{ accountId })
    .returns('selectOpportunityIdsWithPrimaryContact', new Set<Id>());
SalesEngineFactsSelector.instance = (SalesEngineFactsSelector) facts.create(SalesEngineFactsSelector.class);

OpportunityService.validateStageProgression(newOpps, oldMap);

Assert.isTrue(newOpps[0].getErrors()[0].getMessage().contains('Credit Hold'));
Assert.areEqual(1, facts.callCount('selectAccountIdsOnCreditHold'), 'one bulk query');
```

- `Test.createStub()` cannot mock inner classes; stub top-level selectors and services only.
- Split a service that ends in DML into a pure `plan...` method (`@TestVisible`, returns the records it would write)
  and a thin method that writes them, so unit tests assert exactly which rows a rule produces
  (`CaseTeamService.planCaseTeamMembers`, `CaseSlaService.planMilestoneCompletions`).
- `getFakeId` needs a describe key prefix; some setup objects (e.g. `CaseTeamRole`) have none, so build those Ids from
  the literal prefix (`'0B7' + ...`).
- Keep platform engines out of bulk tests unless they are what you are testing: 200 cases on an entitlement add
  ~30s of milestone processing without exercising more Nexus code.
- Use `TestDataFactory.getFakeId(SObjectType)` for record Ids, and `old.clone(true)` to build `Trigger.oldMap` / `Trigger.new` pairs.
- Rules that read a `*FactsSelector` also need one database test running as a user **without** the feature's
  permission sets (see `OpportunityTriggerIntegrationTest.stageGatesApplyToUsersWithoutSalesPermissions`), proving
  the rule holds for integration users, partners and agents.
- Build parent relationships and child lists (e.g. `Manager.IsActive`, `OpportunityContactRoles`) with `JSON.deserialize` -
  see the helpers in `OpportunityServiceTest`.
- Assert on `record.getErrors()` / `record.hasErrors()` instead of catching `DmlException`.

## 3. User Mode in Tests

Selectors run `WITH USER_MODE`, so DML-level tests must act as a user that holds the module's permission set group.
Permissions assigned to the already-running user do not take effect inside a test: create a dedicated user
(`SalesEngineTestFixtures.salesAdmin()`) and wrap the test body in `System.runAs`.

## 4. Gates

`scripts/devops/run-apex-tests.sh` runs every Nexus test class and fails on any failure or when Nexus-only coverage
(package classes such as Nebula Logger excluded) drops below `minApexCoverage` (85%) in `config/devops/nexus-devops.json`.
