# Nexus Core: AI Agent Architecture & Engineering Standards

You are assisting in building **Nexus Core**, an enterprise-grade, modular Salesforce reference platform. All generated code and metadata must strictly adhere to the packaging boundaries, architectural patterns, and security guardrails outlined below.

---

## 1. Scratch Org Bootstrap & Verification Recipe

When executing tasks or testing deployments in an ephemeral scratch org, follow this exact CLI sequence:

```bash
# 1. Create scratch org (Phases 1-4 use headless profile)
sf org create scratch -f config/project-scratch-def-headless.json -a nexus-dev -d 1 --set-default

# 2. Deploy Foundation and Core Domain modules
sf project deploy start -m ApexClass,CustomObject,CustomMetadata,PermissionSet,PermissionSetGroup,Flow,LightningComponentBundle

# 3. Assign Permission Set Group to the default running user
sf org assign permsetgroup -n PSG_Sales_Representative

# 4. Seed sample test data for instant functional verification
sf data import tree --plan data/data-plan.json

# 5. Run in-memory unit tests
sf apex run test -c -r human --code-coverage
```

---

## 2. Core Architectural Guardrails

### 2.1 Pragmatic Clean Architecture Standard
Heavy reflection-based frameworks (`fflib`) are prohibited in Nexus Core in favor of **Pragmatic Clean Architecture**:
- **Triggers:** Triggers must be one line: `new SObjectTriggerHandler().run();`
- **Trigger Handlers:** Must extend `TriggerHandler.cls`. Handlers only route execution context; they contain no business logic or inline SOQL.
- **Selector Layer:** All SOQL queries must reside in dedicated `*Selector.cls` classes, enforcing explicit field selection and `WITH USER_MODE`. Never write inline SOQL in controllers, invocables, or triggers.
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
        @InvocableVariable public String fieldName;
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

## 5. Agentforce, MCP & HXL UI Contracts
- Adhere strictly to the 4-part metadata contract:
  1. CLT Payload (`<action>OutputValues/schema.json`)
  2. CLT Result Wrapper (`<action>Result/schema.json`)
  3. CLT Renderer (`<action>Result/renderer.json`)
  4. HXL UiWidgetBundle (`composition.json` + `schema.json`)
  5. McpServerDefinition (`.mcpServerDefinition-meta.xml`): 
     - Tools point to the Apex class.
     - Resources point to `ui://widget/lightningType/c__<ResultWrapperCLT>`.