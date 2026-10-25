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
assigns permissions, creates the Sales Manager persona, seeds `data/`, and runs all Apex tests.

### What Phase 1 delivers

| Module                                 | Component                                                                                                     | Purpose                                                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `00-foundation/trigger-framework`      | `TriggerHandler`                                                                                              | Context routing, recursion guard (`setMaxLoopCount`), handler bypass                                      |
| `00-foundation/bypass-framework`       | `BypassService`, `Trigger_Setting__mdt`, `Bypass_Triggers` custom permission (granted by `PS_Trigger_Bypass`) | Transactional, org-wide (per object) and per-user trigger bypass                                          |
| `00-foundation/admin-cockpit`          | `OrgLimitsService`, `LogEntriesSelector`, `adminLimitsCockpit` LWC, **Admin Cockpit** tab                     | Live `System.OrgLimits` telemetry (OK < 70% ≤ WARNING ≤ 85% < CRITICAL) and Nebula Logger ERROR/WARN feed |
| `00-foundation/test-framework`         | `TestDataFactory`                                                                                             | Standard-object test builders                                                                             |
| `10-core-domain/sales-engine`          | `OpportunityTrigger` → `OpportunityTriggerHandler` → `OpportunityService`                                     | Discount approval policy and stage gates                                                                  |
|                                        | `OpportunitiesSelector`, `AccountsSelector`, `UsersSelector`                                                  | All SOQL, `WITH USER_MODE`                                                                                |
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
