# Nexus Core: Modular Enterprise Reference Platform

Nexus Core is a modular, enterprise-grade Salesforce reference architecture demonstrating production patterns across:

- **Core Platform:** Standard Sales Cloud (Accounts, Opps, Approvals, Joined Reports), Service Cloud (Cases, Omni-Channel, Case Teams, Entitlements & SLA Milestones), and CapEx (Financial Ledgers, Platform Events).
- **Enterprise Apex & Security:** Pragmatic Clean Architecture (Base TriggerHandler, Domain Services, User-Mode Selectors), Event-Driven Architecture (EDA), Private OWD, `WITH USER_MODE`, Trigger Bypass Framework.
- **Admin Cockpit & Observability:** Real-time `/limits` health telemetry via `System.OrgLimits`, threshold alerts, and centralized Nebula Logger error monitoring.
- **Declarative Governance:** Permission Set Groups (PSGs), automated data seeding plans.
- **OmniStudio:** Integration Procedures (VIPs) as a service facade, Data Mappers, FlexCards.
- **Experience Cloud Dual Runtimes:**
  - **LWR (Lightweight Web Runtime):** High-performance public guest portal, strict LWS, and Content Approval publishing.
  - **Aura Runtime (Partner Central):** Authenticated B2B Partner Portal, Deal Registration approval pipeline, and external role-hierarchy sharing.
- **Analytics & Modern Runtimes:** CRM Analytics decoupled templates and Multi-Framework React 18+ micro-frontends (`UIBundle`).
- **Agentforce & MCP:** Headless Invocable Actions, Custom Lightning Types (CLT), HXL `UiWidgetBundle`, and Model Context Protocol (MCP) server definitions.

## 9 Demonstration Applications

1. **Demo App 1 (Sales Cloud):** Enterprise Sales & Pipeline Engine (`Account`, `Opportunity`, Deal Closer Screen Flow, Multi-Tier Discount Approvals, Joined Reports).
2. **Demo App 2 (Service Cloud):** Omni-Channel Service Desk & SLA Escalation Engine (`Case`, `CaseTeamMember`, Omni-Channel Queues, Entitlement Milestones).
3. **Demo App 3 (CapEx):** Back-Office CapEx & Operations Engine (`CapEx_Request__c`, `Ledger_Entry__c`, Platform Events, Private OWD).
4. **Demo App 4 (OmniStudio):** Service 360 & Operations Intelligence (VIPs, Data Mappers, FlexCards).
5. **Demo App 5 (Experience Cloud LWR):** Hospitality & Guest Experience Portal (LWR, headless Light-DOM, CMS Publication Approval).
6. **Demo App 6 (Experience Cloud Aura):** B2B Partner Central & Deal Registration (Aura runtime, Partner Community licensing, Deal Registration routing).
7. **Demo App 7 (CRM Analytics):** Executive Analytics Intelligence (Data Prep recipes, predictive churn scores).
8. **Demo App 8 (Multi-Framework):** React 18+ Account & Asset Explorer (`UIBundle`, LWS, SLDS tokens).
9. **Demo App 9 (Agentforce & MCP):** Autonomous Hotel Concierge & Booking Service (Invocable Apex, CLTs, HXL Widgets, MCP).

## Phased Delivery Roadmap

- **Phase 1 (Weeks 1–3):** Foundation, Admin Cockpit & Sales Engine (`00-foundation`, `adminLimitsCockpit`, `data/` seed plan, PSGs, Demo App 1).
- **Phase 2 (Weeks 4–5):** DevOps, CI/CD Gates & Quality Auditing (Pre-commit linting, PMD user-mode check, drift detection).
- **Phase 3 (Weeks 6–7):** Service Desk, Omni-Channel, Case Teams & Entitlements (Demo App 2).
- **Phase 4 (Weeks 8–9):** Back-Office CapEx Engine & Event-Driven Architecture (Demo App 3).
- **Phase 5 (Weeks 10–11):** OmniStudio Service Facade & Service 360 (Demo App 4).
- **Phase 6 (Weeks 12–13):** Dual Experience Cloud Runtimes: LWR & Aura Partner Central (Demo Apps 5 & 6).
- **Phase 7 (Weeks 14–15):** CRM Analytics & Multi-Framework React Explorer (Demo Apps 7 & 8).
- **Phase 8 (Weeks 16–17):** Autonomous Agentforce, MCP & HXL UI Stack (Demo App 9).

## Getting Started (Phase 1)

Prerequisites: Salesforce CLI (`sf`), `jq`, Node 18+, and an authorized Dev Hub.

```bash
npm install                                    # LWC Jest tooling
scripts/org-init/setup-scratch-headless.sh --dev-hub DevHubGS
npm test                                       # LWC Jest tests
```

The setup script creates the scratch org, installs Nebula Logger, deploys `00-foundation` + `10-core-domain`,
assigns permissions, configures the service desk, creates the Sales Manager persona, seeds `data/` and the service
desk cases, and runs all Apex tests.

### What Phase 1 delivers

| Module                                 | Component                                                                                                     | Purpose                                                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `00-foundation/trigger-framework`      | `TriggerHandler`                                                                                              | Context routing, recursion guard (`setMaxLoopCount`), handler bypass                                      |
| `00-foundation/bypass-framework`       | `BypassService`, `Trigger_Setting__mdt`, `Bypass_Triggers` custom permission (granted by `PS_Trigger_Bypass`) | Transactional, org-wide (per object) and per-user trigger bypass                                          |
| `00-foundation/admin-cockpit`          | `OrgLimitsService`, `LogEntriesSelector`, `adminLimitsCockpit` LWC, **Admin Cockpit** tab                     | Live `System.OrgLimits` telemetry (OK < 70% ≤ WARNING ≤ 85% < CRITICAL) and Nebula Logger ERROR/WARN feed |
| `00-foundation/test-framework`         | `TestDataFactory`                                                                                             | Standard-object test builders                                                                             |
| `10-core-domain/sales-engine`          | `OpportunityTrigger` → `OpportunityTriggerHandler` → `OpportunityService`                                     | Discount approval policy and stage gates                                                                  |
|                                        | `OpportunitiesSelector` / `SalesEngineFactsSelector`                                                          | Data access `WITH USER_MODE` / rule facts `WITH SYSTEM_MODE` (stage gates, approver routing)              |
|                                        | `CloseOpportunityAction` + **Opportunity Deal Closer** screen flow                                            | Guided close Won/Lost via the uniform invocable result envelope                                           |
|                                        | **Opportunity Discount Approval** process + `Discount_Approval_Tier__mdt`                                     | Tier 1 (> 10%) → owner's manager; Tier 2 (> 25%) → also executive approver                                |
|                                        | `PSG_Sales_Representative` (`PS_Sales_Rep`), `PS_Sales_Admin`, **Nexus Sales** app                            | Access model                                                                                              |
| `10-core-domain/reports`, `dashboards` | **Pipeline vs Won Revenue** (joined), **Open Pipeline by Stage**, **Sales Performance Console**               | Sales performance reporting                                                                               |
| `10-core-domain/org-model`             | Role hierarchy                                                                                                | Executive VP → Sales Manager → Sales Representative; Service Agent                                        |

### Sales engine rules (`OpportunityService`)

- **Discount policy:** `Discount_Percentage__c` maps to `Approval_Tier__c` using `Discount_Approval_Tier__mdt` thresholds (strictly greater than). Lowering an approved discount keeps the approval; raising it resets status to _Not Submitted_. The discount is locked while approval is _Pending_.
- **Executive approver:** owner's manager's manager, falling back to the owner's manager.
- **Closed Won gate:** no account credit hold, discount approval satisfied, and a primary contact role (on update).
- **Closed Lost gate:** `Loss_Reason__c` required.

> Scratch Developer Edition orgs include only 2 Salesforce licenses: the admin user doubles as the Sales Rep persona
> and reports to the generated _Sam Manager_ user, who approves Tier 1 (and, as fallback, Tier 2) discounts.

## Service Desk (Phase 3)

Open the **Nexus Service** console app (`sf org open -p lightning/app/c__Nexus_Service`). New cases are routed by
the active Case assignment rule to the **Tier 1 Support** queue and pushed to agents by Omni-Channel (utility bar →
_Available - Cases_).

| Component (`10-core-domain/service-desk`)                                                             | Purpose                                                                                                           |
| ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `CaseTrigger` → `CaseTriggerHandler` → `CaseEscalationService`, `CaseSlaService`, `CaseTeamService`   | Escalation policy, entitlement linking, milestone completion, case team provisioning                              |
| `CasesSelector` / `ServiceDeskFactsSelector`                                                          | Data access `WITH USER_MODE` / rule facts `WITH SYSTEM_MODE` (queues, roles, entitlements, milestones)            |
| `EscalateCaseAction` + **Escalate Case** screen flow (quick action on the **Nexus Case Record Page**) | Escalate with a reason and optional Technical SME via the uniform invocable result envelope                       |
| **Nexus Standard Support** entitlement process, `First Response` / `Resolution` milestones            | SLA targets by priority (High 1h/8h, Medium 4h/24h, Low 8h/48h); every violation escalates (`SLA_Violated_On__c`) |
| Omni-Channel: `Case_Channel`, `Available_Cases`, `Tier_1_Routing` / `Tier_2_Routing`, two queues      | Most-available push routing; Tier 2 escalations are routed first                                                  |
| `PSG_Service_Agent` (`PS_Service_Agent` + `PS_Omni_Channel_Agent`), **Nexus Service** app             | Access model                                                                                                      |

### Service desk rules

- **Escalation** (one policy for every channel: the Escalate Case flow / Agentforce / MCP, an SLA breach, or an agent
  setting _Status = Escalated_): priority High, owner the **Tier 2 Technical Escalations** queue, `Escalated_On__c`
  stamped, a default reason when none was given, and the reason recorded as a private case comment.
- **Case team:** on escalation the previous owner (if a user) joins as _Escalating Agent_ and keeps access; the
  `Technical_SME__c` user joins as _Technical SME_; when a case becomes High priority the account owner joins as
  _Account Manager_ (read only).
- **SLA:** cases inherit their account's active entitlement (when created with, or later given, an account); moving
  into a working status completes First Response (escalating does not count as a response); closing
  completes Resolution.
- **SLA violations:** every violated milestone escalates the case (unless it is already escalated or closed) and
  stamps `SLA_Violated_On__c`. The entitlement process signals through `SLA_Breached__c`, which the trigger resets.
- Rule facts and side effects (comments, team members, milestone completion) run in system mode; they only follow a
  case change the running user was allowed to make. The escalation itself runs in user mode.

> The admin user also covers the Service Agent persona (2-license limit). The setup script creates the Case Team
> Roles, grants the _Available - Cases_ presence status (not deployable as permission set metadata at API 62), adds
> the admin to both queues and seeds entitlements and five sample cases (`scripts/org-init/seed-service-desk.apex`).
> Open issues and platform constraints (entitlement process versioning, the org-wide Case assignment rule, and
> others) are tracked in [`docs/known-issues.md`](docs/known-issues.md).

## Back-Office CapEx (Phase 4)

Open the **Nexus Operations** app (`sf org open -p lightning/app/c__Nexus_Operations`). A rep raises a CapEx request
and submits it; their manager approves; approval publishes `CapEx_Approved__e`, and the ledger posting reaches the ERP
asynchronously ([ADR 0002](docs/adr/0002-decoupling-via-platform-events.md),
[BP-EDA-002](docs/best-practices/02-event-driven-architecture.md)).

| Component (`10-core-domain/capex-operations`, `base-schema`, `event-bus`)                     | Purpose                                                                                               |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `CapEx_Request__c` (Private OWD) + **CapEx Approval** process                                 | Draft → Submitted → Approved / Rejected; the submitter's manager approves (role hierarchy access)     |
| `CapExRequestTrigger` → `CapExService`                                                        | Draft-only creation, amount/department/title frozen once submitted, publishes `CapEx_Approved__e`     |
| `CapEx_Approved__e` (PublishAfterCommit) → `CapExApprovedTrigger` → `LedgerPostingService`    | Idempotent `Ledger_Entry__c` per request (`Idempotency_Key__c`), row-lock retries via the event bus   |
| `LedgerPostingJob` → `ErpLedgerClient` → `Mock_ERP_Ledger` named credential                   | ERP posting with 1/5/15/30-minute retries up to `ERP_Ledger_Setting__mdt.Max_Attempts__c`, then ERROR |
| `RetryLedgerPostingAction`                                                                    | Re-queue a failed posting (result envelope; Flow / Agentforce / MCP)                                  |
| **Approved CapEx to Finance** criteria-based sharing rule, **Finance Controller** role        | Finance reads requests only once approved                                                             |
| `PS_CapEx_Submitter`, `PS_CapEx_Reviewer`, `PS_CapEx_Admin`, **Nexus Operations** app         | Access model                                                                                          |
| **Departmental CapEx Pipeline**, **CapEx Ledger Posting Status**, **CapEx Executive Console** | Reporting                                                                                             |

> The mock ERP endpoint does not exist, so `ERP_Ledger_Setting.Default.Simulate__c` (on) returns synthetic `SIM-`
> references. The admin raises requests and the generated Sales Manager approves them; the setup script seeds five
> requests (`scripts/org-init/seed-capex.apex`), two of them approved and posted through the real event pipeline.

## Quality Gates & CI (Phase 2)

| Command                                                       | Gate                                                                                                                           |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `npm run verify`                                              | All static gates below, locally (also run by the pre-commit hook for staged files: Prettier + ESLint)                          |
| `npm run format:check` / `npm run lint` / `npm run test:unit` | Prettier, ESLint (LWC), LWC Jest                                                                                               |
| `npm run lint:apex`                                           | Code Analyzer: PMD Recommended + Nexus rules (`WITH USER_MODE`, SOQL only in selectors, one-line triggers, invocable envelope) |
| `npm run test:pmd-rules`                                      | Regression fixtures for the Nexus PMD rules                                                                                    |
| `npm run validate:clt`                                        | Custom Lightning Type / HXL widget / MCP contract validation                                                                   |
| `npm run audit:metadata`                                      | Orphaned metadata and missing permission grants                                                                                |
| `npm run audit:deps`                                          | Module layering, declared and transitive 2GP dependencies ([graph](docs/architecture/module-dependencies.md))                  |
| `scripts/devops/run-apex-tests.sh --target-org <alias>`       | Nexus Apex tests, >= 85% coverage of Nexus classes                                                                             |
| `scripts/devops/drift-detect.sh --target-org <alias>`         | Semantic drift between git and an org                                                                                          |

GitHub Actions: `.github/workflows/ci.yml` (static gates on every PR, scratch org suite on ready PRs) and
`.github/workflows/nightly-drift.yml`. Secrets, branch protection and Dev Hub quota: [docs/devops/github-setup.md](docs/devops/github-setup.md).
Gate configuration (active modules, coverage threshold, allowlist): `config/devops/nexus-devops.json`.
