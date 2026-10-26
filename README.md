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
7. **Demo App 7 (CRM Analytics):** Executive Analytics Intelligence (Data Prep recipe, pipeline dashboard, decoupled `template-info.json` app template).
8. **Demo App 8 (Multi-Framework):** React Account & Asset Explorer (`UIBundle`, React 19, UI API GraphQL, SLDS styling hooks).
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

- **Escalation** (one policy for every channel: the Escalate Case flow / Agentforce / MCP, an SLA breach, an agent
  setting _Status = Escalated_ (a closed case is reopened), or a case created as Escalated): priority High, owner the **Tier 2 Technical Escalations** queue, `Escalated_On__c`
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

| Component (`10-core-domain/capex-operations`, `base-schema`, `event-bus`)                     | Purpose                                                                                                                        |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `CapEx_Request__c` (Private OWD) + **CapEx Approval** process                                 | Draft → Submitted → Approved / Rejected; the submitter's manager approves (role hierarchy access)                              |
| `CapExRequestTrigger` → `CapExService`                                                        | Draft-only creation, amount/department/title frozen once submitted, publishes `CapEx_Approved__e`                              |
| `CapEx_Approved__e` (PublishAfterCommit) → `CapExApprovedTrigger` → `LedgerPostingService`    | Idempotent `Ledger_Entry__c` per request (`Idempotency_Key__c`), row-lock retries via the event bus                            |
| `LedgerPostingJob` → `ErpLedgerClient` → `Mock_ERP_Ledger` named credential                   | ERP posting with 1/5/15/30-minute retries up to `ERP_Ledger_Setting__mdt.Max_Attempts__c`, then ERROR                          |
| `RetryLedgerPostingAction`                                                                    | Re-queue a failed posting, or recover an approval stuck as Pending with no ledger entry (list view **Pending Ledger Posting**) |
| **Approved CapEx to Finance** criteria-based sharing rule, **Finance Controller** role        | Finance reads requests only once approved                                                                                      |
| `PS_CapEx_Submitter`, `PS_CapEx_Reviewer`, `PS_CapEx_Admin`, **Nexus Operations** app         | Access model                                                                                                                   |
| **Departmental CapEx Pipeline**, **CapEx Ledger Posting Status**, **CapEx Executive Console** | Reporting                                                                                                                      |

> The mock ERP endpoint does not exist, so `ERP_Ledger_Setting.Default.Simulate__c` (on) returns synthetic `SIM-`
> references. The admin raises requests and the generated Sales Manager approves them; the setup script seeds five
> requests (`scripts/org-init/seed-capex.apex`), two of them approved and posted through the real event pipeline.

## Service 360 with OmniStudio (Phase 5)

Needs the **full** org shape (OmniStudio standard runtime, no managed package):

```bash
scripts/org-init/setup-scratch-headless.sh --profile full --alias nexus-full --dev-hub DevHubGS
sf org open -o nexus-full -p lightning/app/c__Nexus_Customer_360     # open any Account
```

`FC_CustomerHeader` (FlexCard) → `VIP_Customer360` (Integration Procedure) → `DMCustomer360Extract` (Data Mapper)
plus `Customer360Service` (Apex remote action). The FlexCard runs no SOQL: all data comes through the Integration
Procedure, and the Data Mapper enforces field-level security.

| Component (`modules/20-omnistudio/customer-360`)                 | Purpose                                                                                                                                                               |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DMCustomer360Extract` (Extract Data Mapper)                     | Account, up to 50 open opportunities and 50 open cases for an `AccountId`                                                                                             |
| `VIP_Customer360` (Integration Procedure, input `AccountId`)     | `LogRequest` (Nebula `CallableLogger`, DEBUG, unsaved) → `GetCustomerData` → `SummarizeCustomer` → `ReturnCustomer360`                                                |
| `Customer360Service` (`System.Callable`, action `summarize`)     | Health: **At Risk** (credit hold, escalations, SLA violations), **Watch** (high priority, pending discounts), **Incomplete** (credit status not visible), **Healthy** |
| `FC_CustomerHeader` (FlexCard) on **Nexus Account Customer 360** | Account header with health and key indicators (`runtime_omnistudio:flexcard`, `flexcardName`)                                                                         |
| `PS_Customer360_User`, **Nexus Customer 360** app                | App, Apex access for the remote actions; data access stays with the user's other permission sets                                                                      |

Response shape: `{account: {...}, opportunities: [...], cases: [...], summary: {health, healthVariant, healthReasons,
complete, creditHold, openOpportunities, openPipelineAmount, pendingDiscountApprovals, openCases, highPriorityCases,
escalatedCases, slaViolations}}`.

### Click-through checklist (runtime verification, KI-025)

The components deploy, activate and round-trip, and `Customer360Service` is unit-tested, but an Integration
Procedure cannot be executed and a FlexCard cannot be rendered from the CLI. In a full-profile org:

1. **App Launcher → OmniStudio → Integration Procedures → `VIP_Customer360` → Preview** with
   `{"AccountId": "<Globex Retail Group Id>"}`. Expect `account.Name = "Globex Retail Group"`, one open opportunity,
   one open case (Escalated, High) and `summary.health = "At Risk"` with reasons "Account is on credit hold; 1
   escalated case(s); 1 high-priority case(s)".
2. In the Preview debug output, confirm `GetCustomerData` returned only open records (the Data Mapper filters
   `IsClosed = 'false'`; `Customer360Service` skips closed records either way).
3. **Nexus Customer 360** app → open each seeded account and check the header renders. Expected health:
   Globex Retail Group **At Risk**, Acme Global Manufacturing **Watch** (one High-priority case), Apex Healthcare
   Solutions and Nexus Global Channel Partners **Healthy**.
4. **Logger Console → Log Entries**: a normal view saves no log entry. `LogRequest` adds a DEBUG entry that is
   saved only when a later step fails and saves the log (e.g. `Customer360Service` logging an error).
5. As a user without `PS_Customer360_User`, the header shows an error instead of data (no Apex access). With
   `PS_Customer360_User` but without sales or service permission sets, health still reflects the credit hold and
   cases (the permission set grants read access to every field the health rules use).

Report anything that differs; fixes go in a follow-up.

## Experience Cloud: Hospitality Portal & Partner Central (Phase 6)

Full profile (`setup-scratch-headless.sh --profile full`), [ADR 0004](docs/adr/0004-dual-experience-cloud-runtimes.md).
Back office: **Nexus Portals** app. Sites: Setup → Digital Experiences → All Sites.

| Component (`modules/30-experience-cloud`)                                                                      | Purpose                                                                                                                                                                                                                                                   |
| -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Nexus Hospitality** (LWR, `DigitalExperienceBundle`, public access), `/hospitality`                          | Public portal; home page shows `hospitalityArticles` (Light DOM LWC)                                                                                                                                                                                      |
| `Portal_Article__c` + **Portal Content Approval** (author's manager)                                           | Draft → In Review → Published; only Published articles are visible to the site guest user (guest sharing rule)                                                                                                                                            |
| `PortalContentController` → `PortalContentService` → `PortalArticlesSelector` (user mode)                      | Guest reads under the guest user's own sharing and field access; no `without sharing`                                                                                                                                                                     |
| **Nexus Partner Central** (Aura, `ExperienceBundle`, Partner Central template, PRM), `/partners`               | Partner portal; home page sidebar runs the **Partner Deal Registration** flow                                                                                                                                                                             |
| `Deal_Registration__c` + **Deal Registration Approval** (channel manager = partner account owner)              | Private OWD; partner role hierarchy; approval locks the registration, creates the customer account and opportunity (shared read-only with the partner) and reserves the customer for 90 days or until the opportunity closes; a recall marks it Withdrawn |
| `DealRegistrationService`, `DealRegistrationFactsSelector`, `SubmitDealRegistrationAction`                     | Routing, channel conflict rule (one live reservation per customer across partners), conversion; `DealRegistrationExpiryJob` (daily) marks lapsed reservations Expired / Closed                                                                            |
| `PS_Portal_Content_Author`, `PS_Partner_Deal_Registration`, `PS_Channel_Manager`, `Nexus Partner User` profile | Access model                                                                                                                                                                                                                                              |

Personas: the admin authors content and the Sales Manager approves it; the Sales Manager is also the channel manager
who owns **Nexus Global Channel Partners**, whose contact **Tom Alvarez** is the partner user (Partner Community
license). Site metadata carries two deploy-time placeholders (`sfdx-project.json` `replacements`):
`NEXUS_SITE_ADMIN` and `NEXUS_SITE_EMAIL`, which the setup script exports.

### Click-through checklist (runtime verification, KI-030)

Verified from the CLI: guest record access (the guest user reads the three Published articles, not the draft), the
public site answers HTTP 200, and a deal registration owned by Tom routes to the Sales Manager, converts on approval
and blocks a second registration for the same customer. Still to check in a browser:

1. **Public portal:** in a private window open `https://<my-domain>.scratch.my.site.com/hospitality`. Expect the
   welcome heading and three article cards (Spring spa escape, Harbour lights festival, Packing for a city break);
   the draft "Summer rooftop menu" must not appear.
2. **Publishing:** in **Nexus Portals → Portal Articles**, create an article and **Submit for Approval**. Log in as
   Sam Manager (Setup → Users → Login) and approve it. Reload the portal: the new article appears.
3. **Partner registration:** open Tom Alvarez's contact → **Log in to Experience as User** → Nexus Partner Central.
   Complete **Register a Deal** in the sidebar: expect the success screen. Register the same customer again: expect
   "Channel conflict: ...".
4. **Approval:** as Sam Manager, approve the registration (Approval Requests). Its **Opportunity** field links to the
   new opportunity, owned by Sam, with Lead Source "Partner Referral".
5. **Partner visibility:** as Tom, open `/partners/s/recordlist/Deal_Registration__c/Default`: Tom sees his own
   registrations only, and the approved registration's **Opportunity** link opens (read only). The registration is
   locked and shows **Reservation Expires On** 90 days out.

## CRM Analytics & Multi-Framework React (Phase 7)

Full profile (`setup-scratch-headless.sh --profile full`), [ADR 0006](docs/adr/0006-analytics-templates-and-ui-bundles.md).

### Demo App 7: Executive Analytics (`modules/40-crm-analytics`)

| Component                                                        | Purpose                                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `waveTemplates/Nexus_Executive_Analytics` (`WaveTemplateBundle`) | Decoupled app template: `template-info.json` lists the recipe, dataset and dashboard the app is created from  |
| `recipes/Nexus_Pipeline_Recipe.json` (Data Prep, R3)             | Loads Opportunity and Account (connected objects, `SFDC_LOCAL`), looks up the account, saves `Nexus_Pipeline` |
| `dashboards/Nexus_Pipeline_Overview.json`                        | Open pipeline and Closed Won tiles, pipeline by stage, open pipeline by industry (SAQL steps)                 |

Only the template is source. The setup script deploys it and then creates the **Nexus Executive Analytics** app from
it (`sf analytics app create --templatename`, listed in `nexus-devops.json` `analyticsTemplates`), which syncs the
connected objects and runs the recipe. The admin gets **CRM Analytics Plus Admin** (`EinsteinAnalyticsPlusAdmin`).

To change the analytics: edit the app in Analytics Studio, recreate the template from it
(`sf analytics template create -f <folderId> -r <recipeId>`), retrieve `WaveTemplateBundle:Nexus_Executive_Analytics`
at API 66.0, and check the diff for org Ids and usernames (KI-039).

### Demo App 8: Account & Asset Explorer (`modules/50-multi-framework`)

| Component                                                    | Purpose                                                                                                           |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `uiBundles/NexusAssetExplorer` (`UIBundle`, React 19 + Vite) | Account search (debounced) and an account panel: asset stats, installed base value, open cases, asset table       |
| `src/api/explorerApi.ts`                                     | Two UI API GraphQL queries through `@salesforce/platform-sdk`; results respect the user's object and field access |
| `src/styles/slds-tokens.css`                                 | `.nx-*` classes on SLDS global styling hooks (`--slds-g-*`) with fallbacks                                        |
| `PS_Asset_Explorer_User`                                     | Read on Account, Asset, Case and Product2, and asset field access                                                 |
| `scripts/org-init/seed-assets.apex`                          | Three products and six installed assets for Acme, Globex and Apex Healthcare (idempotent)                         |

The bundle is built before deployment (`npm run test:ui-bundles` runs Vitest, the type check and the Vite build; the
setup script builds with `--skip-tests`). Only `dist/` and the bundle metadata deploy (`.forceignore`), from a
manifest at API 66.0 (`deployApiVersions`, KI-038).

### Click-through checklist (runtime verification, KI-037)

Verified from the CLI: both GraphQL queries return data as the admin; the app created from the template ran the
recipe (`Nexus_Pipeline` returns pipeline by stage through SAQL); drift is clean. Still to check in a browser:

1. **Explorer:** App Launcher → **Nexus Asset Explorer**. Expect the account list; type "Glo" to filter it to the
   three accounts with "Glo" in the name. Select **Acme Global Manufacturing**: three assets, the installed base
   value, and two open cases.
2. **Styling and LWS:** the explorer follows the org's SLDS theme (fonts, borders, brand colour on the selected
   account) and the browser console shows no Lightning Web Security violations.
3. **Analytics:** `sf org open -o <alias> -p lightning/n/standard-AnalyticsStudio` → **Nexus Executive Analytics** →
   **Nexus Pipeline Overview**. Expect the two number tiles, the stage bar chart and the industry donut; selecting a
   stage bar filters the other widgets.

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
