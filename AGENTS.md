# Nexus Core: AI Agent Architecture & Engineering Standards

You are assisting in building **Nexus Core**, an enterprise-grade, modular Salesforce reference platform. All generated code and metadata must strictly adhere to the packaging boundaries, architectural patterns, and security guardrails outlined below.

---

## 1. Scratch Org Bootstrap & Verification Recipe

When executing tasks or testing deployments in an ephemeral scratch org, use the bootstrap script (Phases 1-4, headless profile; add `--profile full` for Phase 5+ modules such as OmniStudio, which also uses `config/project-scratch-def-full.json`):

```bash
scripts/org-init/setup-scratch-headless.sh --alias nexus-dev --dev-hub DevHubGS --days 1
# Re-run against an existing org: add --skip-create; skip the test run: add --skip-tests
```

It performs this sequence (verified on Salesforce CLI 2.155):

```bash
# 1. Create scratch org (-y = duration in days; -d means --set-default in current CLI versions)
sf org create scratch -f config/project-scratch-def-headless.json -a nexus-dev -y 1 --set-default

# 2. Install Nebula Logger (unlocked, no namespace) - 00-foundation depends on it
sf package install -o nexus-dev --package 04tg7000000IzRdAAK --security-type AdminsOnly --wait 20 --no-prompt

# 3. Deploy Foundation and Core Domain modules by source directory (ADR 0005 inner loop). Queues go first: the
#    Case assignment rule cannot reference a queue created in the same deployment.
sf project deploy start -m Role -m QueueRoutingConfig -m Queue
sf project deploy start -d modules/00-foundation -d modules/10-core-domain

# 4. Permissions: there is no `sf org assign permsetgroup`; PSGs are assigned via a PermissionSetAssignment record
sf org assign permset -n PS_Nexus_Admin -n PS_Sales_Admin -n LoggerAdmin
sf data create record -s PermissionSetAssignment -v "AssigneeId=<adminUserId> PermissionSetGroupId=<PSG_Sales_Representative Id>"
#    (same for PSG_Service_Agent)
sf org assign permset -n PS_CapEx_Submitter -n PS_CapEx_Admin      # admin raises CapEx; Sales Manager gets PS_CapEx_Reviewer

# 4b. Service desk org data the Metadata API cannot deploy: CaseTeamRole records (Technical SME, Escalating Agent,
#     Account Manager), SetupEntityAccess granting the Available_Cases presence status to PS_Omni_Channel_Agent,
#     and GroupMember rows adding the admin to the Tier_1_Support / Tier_2_Technical_Escalations queues

# 5. Create the Sales Manager persona (config/users/) and set it as the admin user's manager (approval routing)

# 6. Seed sample test data for instant functional verification
sf data import tree --plan data/data-plan.json
sf apex run -f scripts/org-init/seed-service-desk.apex   # entitlements + sample cases (idempotent)
sf apex run -f scripts/org-init/seed-capex.apex          # CapEx requests via the approval process (idempotent)

# 7. Run Nexus Apex tests with the coverage gate (every *Test.cls in the active modules; RunLocalTests would
#    also run ~1,300 Nebula Logger tests)
scripts/devops/run-apex-tests.sh --target-org nexus-dev
```

Active modules (deployed, audited, tested) are listed in `config/devops/nexus-devops.json` `activeModules`; add a module there when its phase starts. Modules that need the full org shape (OmniStudio, Experience Cloud, CRM Analytics) go in `fullProfileModules`: the static gates audit them, but they deploy and test only with `--profile full` (`setup-scratch-headless.sh`, `run-apex-tests.sh`, `drift-detect.js`), not in CI Gate 3. Later-phase scaffolding inside an active module that does not deploy yet is listed in `.forceignore`; remove those entries as each phase is implemented.

### 1.1 Quality Gates (run before every commit / PR)

```bash
npm run verify   # Prettier, ESLint, LWC Jest, CLT/HXL schemas, module boundaries, orphaned metadata, PMD + Nexus rules
```

CI (`.github/workflows/ci.yml`) runs the same gates plus the scratch org Apex suite (>= 85% Nexus coverage). Do not weaken a gate to make it pass: fix the code, or add a reasoned, phase-tagged entry to the `allowlist` in `config/devops/nexus-devops.json`.

Open review findings and platform constraints live in `docs/known-issues.md`. Check it before changing an affected area, add an entry for any issue you defer, and delete the entry (citing its ID in the commit) when you resolve it.

---

## 2. Core Architectural Guardrails

### 2.1 Pragmatic Clean Architecture Standard

Heavy reflection-based frameworks (`fflib`) are prohibited in Nexus Core in favor of **Pragmatic Clean Architecture**:

- **Triggers:** Triggers must be one line: `new SObjectTriggerHandler().run();`
- **Trigger Handlers:** Must extend `TriggerHandler.cls`. Handlers only route execution context; they contain no business logic or inline SOQL.
- **Selector Layer:** All SOQL queries must reside in dedicated `*Selector.cls` classes, enforcing explicit field selection and `WITH USER_MODE`. Never write inline SOQL in controllers, invocables, or triggers. Selectors are `virtual` instances obtained via `XSelector.newInstance()` so unit tests can replace them with `TestStub` mocks (`XSelector.instance = (XSelector) new TestStub().returns(...).create(XSelector.class)`). These rules are enforced by the Nexus PMD ruleset (`config/pmd/nexus-apex-rules.xml`).
- **Access Mode Follows Purpose:** `WITH USER_MODE` is for _data access_ (records read on behalf of a user and returned, displayed or acted upon). Business _rule enforcement_ (stage gates, approval routing, invariants evaluated in triggers) must not depend on who saves the record (integration users, partners, agents), so its queries live in a `virtual without sharing` `*FactsSelector` using `WITH SYSTEM_MODE`. Facts selector methods answer a narrow question and return Ids, flags or hierarchy-only records; results never leave the service, and `*FactsSelector` classes must not be called from `@AuraEnabled`, `@InvocableMethod` or REST classes (enforced by PMD and `npm run audit:metadata`). Reference: `SalesEngineFactsSelector`. System automation that acts for no person (platform event consumers run as the Automated Process user; queueable jobs) also reads through a `*FactsSelector` and writes in system mode; such methods may return the minimal records the job processes (`CapExFactsSelector.selectPendingEntries`). Event-driven rules: `docs/best-practices/02-event-driven-architecture.md`.
- **Domain Service Layer:** All business logic, validations, and DML orchestration belong in `*Service.cls` classes.
- **Observability:** Log all caught exceptions using `Nebula Logger` (`Logger.error()`, `Logger.saveLog()`).

### 2.2 Packaging & Module Dependencies

The project follows a multi-package layout under `modules/`. Modules must only depend downward:

```text
modules/
├── 00-foundation          (No upstream dependencies)
├── 10-core-domain         (Depends on 00-foundation)
├── 20-omnistudio          (Depends on 10-core-domain)
├── 30-experience-cloud    (Depends on 10-core-domain)
├── 40-crm-analytics       (Depends on 10-core-domain)
├── 50-multi-framework     (Depends on 10-core-domain)
├── 60-hxl-widgets         (Depends on 10-core-domain)
└── 70-agentforce-mcp      (Depends on 10-core-domain & 60-hxl-widgets)
```

### 2.3 Admin Cockpit & Telemetry

- Query org-level resource health using native `System.OrgLimits.getMap()` via `OrgLimitsService.cls`. Do not perform external HTTP callouts to `/limits` from LWC.
- Alert thresholds: OK (< 70%), WARNING (70% - 85%), CRITICAL (> 85%).
- Display system health and error feeds inside `adminLimitsCockpit` LWC.

---

## 3. Invocable Action & Headless Fabric Standards

All `@InvocableMethod` actions exposed to Flows, Agentforce, or MCP must implement the uniform typed result envelope:

```apex
public with sharing class ActionName {
  public class Request {
    @InvocableVariable(required=true label='...')
    public String inputParam;
  }
  public class Result {
    @InvocableVariable(label='Is Success')
    public Boolean isSuccess;
    @InvocableVariable(label='Error Code')
    public String errorCode;
    @InvocableVariable(label='Error Message')
    public String errorMessage;
    @InvocableVariable(label='Payload')
    public OutputPayload payload;
  }
  public class OutputPayload {
    @InvocableVariable
    public String fieldName;
  }
  @InvocableMethod(label='Action Label' category='Domain')
  public static List<Result> execute(List<Request> requests) {
    return DomainService.executeAction(requests);
  }
}
```

---

## 4. Experience Cloud Standards (LWR vs. Aura)

- **LWR (Lightweight Web Runtime):** Use for unauthenticated guest/public portals (`lwr-portal/`). Metadata format is `DigitalExperienceBundle`. Must use Light DOM and comply with strict Lightning Web Security (LWS).
- **Aura Runtime (Partner Central):** Use for authenticated B2B partner portals (`aura-partner-central/`). Metadata format is `ExperienceBundle`. Standard record detail layouts, Deal Registration flows, and Partner Community role sharing.

---

## 4.1 OmniStudio (Standard Runtime)

- Core OmniStudio objects only (no managed package). Orgs need `OmniStudioSettings.enableOmniStudioMetadata` (irreversible; in `project-scratch-def-full.json`). Component names: letters, digits and underscores only.
- Source formats: Data Mappers `omniDataTransforms/<Name>_<version>.rpt-meta.xml`, Integration Procedures `omniIntegrationProcedures/<Type>_<SubType>_<Language>_<version>.oip-meta.xml`, FlexCards `omniUiCard/<Name>_<Author>_<version>.ouc-meta.xml`. Step and card configuration is JSON in `propertySetConfig` / `dataSourceConfig`.
- FlexCards read data only through Integration Procedures (`dataSource.type = "IntegrationProcedures"`); Integration Procedures read through Data Mappers with `fieldLevelSecurityEnabled = true`; logic goes in a `System.Callable` Apex remote action (`Customer360Service`); log with Nebula `CallableLogger` steps.
- OmniStudio validates references at deploy time: deploy Data Mappers after the fields they map and Integration Procedures after their Data Mappers and Apex. `setup-scratch-headless.sh --profile full` deploys full-profile modules in stages (classes + Data Mappers → Integration Procedures → rest) and activates each stage (deployed components can arrive inactive). Place FlexCards with `runtime_omnistudio:flexcard` (`flexcardName`).
- There is no Apex or REST API to execute an Integration Procedure in core runtime: unit-test the Apex remote actions and verify the procedure in the designer Preview (README, Phase 5 checklist).

## 5. Agentforce, MCP & HXL UI Contracts

- Adhere strictly to the 4-part metadata contract:
  1. CLT Payload (`<action>OutputValues/schema.json`)
  2. CLT Result Wrapper (`<action>Result/schema.json`)
  3. CLT Renderer (`<action>Result/renderer.json`)
  4. HXL UiWidgetBundle (`composition.json` + `schema.json`)
  5. McpServerDefinition (`.mcpServerDefinition-meta.xml`):
     - Tools point to the Apex class.
     - Resources point to `ui://widget/lightningType/c__<ResultWrapperCLT>`.
