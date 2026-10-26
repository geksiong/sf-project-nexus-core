# Known Issues & Platform Constraints

Open findings from code reviews and platform constraints discovered during implementation. Each entry says what
happens, why it matters, and the proposed resolution. When an entry is resolved, delete it and mention the ID in the
commit message.

**Status:** _Decision_ = needs a product/owner decision before work starts; _Open_ = agreed, not yet done;
_Constraint_ = platform limitation with a workaround in place; _Verify_ = suspected, needs a manual check.

| ID     | Area         | Status     | Summary                                                                 |
| ------ | ------------ | ---------- | ----------------------------------------------------------------------- |
| KI-002 | Service desk | Verify     | Escalate Case flow: "optional" Technical SME may be required            |
| KI-003 | UI           | Verify     | Phase 1 and Phase 3 screens not exercised in a browser                  |
| KI-004 | Sales        | Open       | Discount approval status is protected only by field-level security      |
| KI-005 | Sales        | Open       | Opportunities created before deployment have no approval tier           |
| KI-006 | Sales        | Open       | Full standard Opportunity layout in source overwrites org layouts       |
| KI-007 | Seed data    | Open       | Fixed close dates and non-standard lead sources                         |
| KI-008 | Service desk | Constraint | Entitlement processes cannot be redeployed once in use                  |
| KI-009 | Service desk | Constraint | The Case assignment rule is org-wide                                    |
| KI-010 | Service desk | Constraint | Service desk org data is created by script, not metadata                |
| KI-011 | Service desk | Constraint | Milestone tracker component unavailable to source; related list used    |
| KI-012 | Security     | Open       | Technical SME field grants case edit access to any active user          |
| KI-013 | DevOps       | Open       | Scratch org bootstrap exceeds the Phase 1 "< 2 minutes" target          |
| KI-014 | DevOps       | Open       | Apex suite exceeds the Phase 1 "< 15s" budget                           |
| KI-015 | DevOps       | Open       | Non-blocking Code Analyzer findings                                     |
| KI-016 | DevOps       | Open       | No 2GP release path yet                                                 |
| KI-017 | DevOps       | Open       | CI is not active until the repository is pushed and secrets are set     |
| KI-020 | CapEx        | Constraint | Criteria-based sharing cannot be asserted in Apex tests                 |
| KI-021 | Reporting    | Constraint | Joined report on the CapEx custom report type is rejected ("Obsolete")  |
| KI-022 | CapEx        | Constraint | ERP integration is simulated; named credential is the legacy format     |
| KI-023 | CapEx        | Open       | CapEx status can be set directly by administrators                      |
| KI-024 | CapEx        | Verify     | One unreproduced posting-test failure on the first run after deploy     |
| KI-025 | OmniStudio   | Verify     | Phase 5 runtime (IP execution, FlexCard rendering) not exercised         |
| KI-026 | OmniStudio   | Constraint | No Apex/REST entry point to run an Integration Procedure in core runtime |
| KI-027 | OmniStudio   | Constraint | Components deploy inactive; API-activated FlexCards generate no LWC      |
| KI-028 | OmniStudio   | Constraint | `enableOmniStudioMetadata` is irreversible and restricts names           |
| KI-029 | DevOps       | Open       | Full- and agentforce-profile modules are not deployed or tested in CI    |
| KI-030 | Experience   | Verify     | Phase 6 pages not exercised in a browser                                 |
| KI-031 | Experience   | Constraint | Site metadata holds org-specific values (deploy-time placeholders)       |
| KI-032 | Experience   | Constraint | Retrieved site bundles can contain properties the deploy schema rejects  |
| KI-033 | Experience   | Constraint | Site bundles embed regenerated content Ids (drift is advisory)           |
| KI-034 | Experience   | Constraint | Standard external profiles cannot create users; custom profile perms ignored |
| KI-036 | Experience   | Constraint | Guest Apex responses are CDN-cached: unpublished content can linger      |
| KI-037 | Analytics/UI | Verify     | Phase 7 dashboard and React explorer not exercised in a browser          |
| KI-038 | DevOps       | Constraint | UIBundle and WaveTemplateBundle deploy only at API 66.0 (manifest deploy) |
| KI-039 | Analytics    | Constraint | The analytics app is created from the template, not deployed             |
| KI-040 | Agentforce   | Verify     | Phase 8 widget rendering and MCP client connection not exercised          |
| KI-041 | Agentforce   | Constraint | Agentforce profile: specific Dev Hub, beta HXL formats, not in CI         |
| KI-042 | Agentforce   | Constraint | Agent and MCP activation are org state; re-publishing makes a new version |

---

## Service desk (Phase 3)


### KI-002 Escalate Case flow: "optional" Technical SME may be required — _Verify_

- **What happens:** the `Technical_SME` lookup in `Case_Escalate.flow-meta.xml` has `isRequired = true`. For
  extension components this flag may not control whether a value is needed (the lookup's own `required` input does),
  but if it does, the field labelled "optional" is mandatory.
- **Resolution:** open the flow from the Escalate Case action; if a value is required, set `isRequired` to `false`.

### KI-008 Entitlement processes cannot be redeployed once in use — _Constraint_

- **What happens:** once entitlements reference **Nexus Standard Support**, any deploy that includes it fails with
  _"Cannot update SLA process that is in use"_, even when the file is unchanged.
- **Workaround in place:** `setup-scratch-headless.sh` detects an existing process and deploys from a manifest that
  omits `EntitlementProcess`. Fresh orgs (CI) deploy it normally. The automatic-escalation design deliberately avoids
  changing the process: the violation action sets the `SLA_Breached__c` signal and `CaseEscalationService` resets it
  and stamps `SLA_Violated_On__c`, so every violation escalates without a new process version.
- **To change SLA targets or actions:** create a new process version (`versionNumber`, `versionMaster`,
  `isVersionDefault` in the metadata, or Setup → Entitlement Processes → New Version), then move existing
  entitlements to the new version (cases keep the version they started with). Plan this as a release step for any
  long-lived org.

### KI-009 The Case assignment rule is org-wide — _Constraint_

- **What happens:** `assignmentRules/Case.assignmentRules-meta.xml` (`Nexus_Tier_1_Intake`, active) replaces the
  org's active Case assignment rule when deployed to a sandbox or production org.
- **Resolution:** before deploying outside scratch orgs, merge the rule entry into the target org's existing rule,
  or exclude the file and assign the Tier 1 queue another way.

### KI-010 Service desk org data is created by script, not metadata — _Constraint_

- **What happens:** three things the Metadata API cannot deploy (API 62) are created by the setup script:
  `CaseTeamRole` records (Technical SME, Escalating Agent, Account Manager); `SetupEntityAccess` granting the
  _Available - Cases_ presence status to `PS_Omni_Channel_Agent` (presence statuses are not supported in permission
  set metadata); and queue membership for the admin (who holds the Sales Representative role, not Service Agent).
  CaseTeamRole records cannot be deleted through the API.
- **Impact:** a sandbox or production deployment needs the same steps; without the roles, `CaseTeamService` logs
  an error and skips members. Re-check presence status support when raising `sourceApiVersion`.

### KI-011 Milestone tracker component unavailable to source — _Constraint_

- **What happens:** the Lightning App Builder _Milestones_ component's API name could not be found (several
  candidates were rejected at deploy), so the **Nexus Case Record Page** shows the Case Milestones related list.
- **Resolution:** add the component in App Builder, retrieve the page, and commit the generated XML.

### KI-012 Technical SME field grants case edit access to any active user — _Open_

- **What happens:** anyone who can edit `Case.Technical_SME__c` (agents, via `PS_Service_Agent`) can add any active
  user to the case team with the _Technical SME_ role (Edit access). This is by design for the demo, but it is a
  sharing grant controlled by a field.
- **Resolution (if needed):** restrict the lookup with a filter (e.g. users holding a custom permission such as
  `Technical_SME`), or make the role Read only.

---

## UI (all phases)

### KI-003 Screens not exercised in a browser — _Verify_

- **What happens:** the Apex behind every screen is tested, but nobody has clicked through the Opportunity Deal
  Closer flow and quick action, the Admin Cockpit page, the Sales Performance dashboard, the Escalate Case flow, the
  Omni-Channel utility or the Nexus Case Record Page.
- **Known cosmetic issue:** Deal Closer shows "Discount: % (Not Required)" for an opportunity without a discount.

## Sales engine (Phase 1)

### KI-004 Discount approval status is protected only by field-level security — _Open_

- **What happens:** `PS_Sales_Admin` can edit `Discount_Approval_Status__c`, so a sales admin can set _Approved_
  directly and bypass the approval process. Intended for admins, but there is no audit trail beyond field history.
- **Resolution:** a validation rule allowing status changes only from the approval process (or a bypass custom
  permission), or field history tracking on the status.

### KI-005 Opportunities created before deployment have no approval tier — _Open_

- **What happens:** `Approval_Tier__c` is derived when the discount changes, so existing discounted opportunities in
  a sandbox or production org have no tier and pass the Closed Won discount gate.
- **Resolution:** a one-off backfill (batch or anonymous Apex re-saving discounted open opportunities) as part of
  the first deployment to a long-lived org.

### KI-006 Full standard Opportunity layout in source — _Open_

- **What happens:** `sales-engine/layouts/Opportunity-Opportunity Layout.layout-meta.xml` holds the whole standard
  layout (needed to place the Deal Closer action). Deploying it overwrites the target org's layout changes.
- **Resolution:** follow the Phase 3 pattern: an app-scoped Lightning record page with the action (as the **Nexus
  Case Record Page** does for Case), and remove the layout from source.

### KI-007 Seed data: fixed close dates and non-standard lead sources — _Open_

- **What happens:** `data/opportunities.json` uses fixed close dates, so open deals become past due over time; it
  also uses lead source values ("Trade Show", "Direct Referral") that are not on the standard picklist.
- **Resolution:** set close dates relative to today in the setup script (or seed opportunities from anonymous Apex
  like the service desk), and use standard picklist values.

## DevOps & quality

### KI-013 Scratch org bootstrap exceeds "< 2 minutes" — _Open_

- **What happens:** creating the org takes ~15s, but installing Nebula Logger takes ~150s; a full bootstrap with
  tests takes ~5.5 minutes (Phase 3 fresh-org run: 342s).
- **Resolution:** accept and restate the target as "excluding package installs", or use a scratch org snapshot /
  org shape with Nebula preinstalled.

### KI-014 Apex suite exceeds the Phase 1 "< 15s" budget — _Open_

- **What happens:** with the service desk the suite runs in ~34–38s; the 200-case bulk escalation test alone takes
  ~10s (platform cost of 400 case team members and 200 comments).
- **Resolution:** set a per-phase budget, keep platform engines out of bulk tests, and push more rules into
  in-memory unit tests.

### KI-015 Non-blocking Code Analyzer findings — _Open_

- **What happens:** Code Analyzer reports ~30 Moderate and ~130 Low findings (mostly missing ApexDoc tags, Boolean
  parameters, empty virtual methods in `TriggerHandler`, complexity in `OpportunityService`). Only High and above
  block CI.
- **Resolution:** burn down Moderate findings; consider raising the gate to Moderate afterwards.

### KI-016 No 2GP release path yet — _Open_

- **What happens:** `sfdx-project.json` declares full dependency chains, but no packages exist in the Dev Hub and
  there is no release workflow, so `sf package version create` cannot run.
- **Resolution:** create the packages (`sf package create`), record their IDs in `packageAliases`, and add a release
  workflow.

### KI-017 CI is not active — _Open_

- **What happens:** the repository has not been pushed. Until it is, and until the `SF_DEVHUB_AUTH_URL` (CI) and
  `SF_TARGET_ORG_AUTH_URL` (nightly drift) secrets and branch protection are set, no workflow runs.
- **Resolution:** follow `docs/devops/github-setup.md`.

## Back-office CapEx (Phase 4)

### KI-020 Criteria-based sharing cannot be asserted in Apex tests — _Constraint_

- **What happens:** the platform writes criteria-based share rows when the transaction commits. Apex test
  transactions never commit (`Test.stopTest()` does not flush them), so the positive case of **Approved CapEx to
  Finance** cannot be asserted. `CapExLifecycleIntegrationTest` covers the hierarchy, peers and "no access before
  approval"; the rule itself was verified in a scratch org (an approved request gets a `Rule` share, Read, to the
  Finance Controller role group). The Phase 6 guest sharing rule (Published `Portal_Article__c` to the Nexus
  Hospitality guest user) has the same limitation; it was verified with `UserRecordAccess` for the guest user.
- **Resolution:** keep the org check in the release checklist, or add a post-deploy smoke script that approves a
  request and queries `CapEx_Request__Share`.

### KI-021 Joined report on the CapEx custom report type is rejected — _Constraint_

- **What happens:** a joined (MultiBlock) report on `CustomEntity$CapEx_Request__c` fails to deploy with
  "Report is Obsolete" for every `joinTable` value tried (`CapEx_Request__c`, lower case, the report type name),
  although summary and matrix reports on the same type deploy. The Phase 4 scaffold's joined report (which also
  mixed in Cases without a common field) was replaced by the **Departmental CapEx Pipeline** matrix report.
- **Resolution (optional):** build the joined report in Report Builder, retrieve it, and compare the XML.

### KI-022 ERP integration is simulated; named credential is the legacy format — _Constraint_

- **What happens:** `Mock_ERP_Ledger` points at a non-existent host, so `ERP_Ledger_Setting.Default.Simulate__c` is
  on and `ErpLedgerClient` returns `SIM-` references without a callout. The named credential uses the legacy
  format (`principalType` / `protocol`), which Salesforce has superseded with External Credentials.
- **Resolution:** to integrate a real ERP, migrate to a named credential + external credential (with a principal
  and permission set mapping), point it at the ERP, and turn simulation off.

### KI-023 CapEx status can be set directly by administrators — _Open_

- **What happens:** `PS_CapEx_Admin` can edit `Status__c`, so an admin can set _Approved_ without the approval
  process, which also publishes `CapEx_Approved__e` (the bulk test relies on this). Same class of issue as KI-004.
  It can also desynchronise the ledger: setting an approved request back to Draft, changing the amount and
  re-approving publishes a second event, which the idempotent consumer correctly skips, so the ledger keeps the
  original amount without any warning.
- **Resolution:** a validation rule allowing status changes only from the approval process (or a bypass custom
  permission for data migration).

### KI-024 One unreproduced posting-test failure on the first run after deploy — _Verify_

- **What happens:** the very first run of the CapEx tests after the classes were first deployed failed
  `approvalPublishesAnEventThatPostsToTheLedger` and `opsAdminRequeuesAFailedPosting`: the ledger entry stayed
  Pending with no error, as if the posting job never ran. Every later run passed (five runs, including one with the
  admin's CapEx permission sets removed), so it is not a permission dependency. A fresh-org bootstrap (first run after deploy) also passed.
- **Resolution:** watch CI. If it recurs, capture the debug log of the event delivery and the job.

## Service 360 / OmniStudio (Phase 5)

### KI-025 Phase 5 runtime not exercised — _Verify_

- **What happens:** `DMCustomer360Extract`, `VIP_Customer360` and `FC_CustomerHeader` deploy, activate and
  round-trip without drift, and `Customer360Service` is unit-tested, but the Integration Procedure was never executed
  and the FlexCard never rendered (no browser, no runtime API: KI-026). The property-set JSON was hand-authored and
  the Data Mapper's literal filter (`IsClosed = 'false'`) syntax is unconfirmed.
- **Resolution:** run the README "Click-through checklist" (Phase 5) and fix what differs.

### KI-026 No Apex/REST entry point to run an Integration Procedure in core runtime — _Constraint_

- **What happens:** core runtime has no `IntegrationProcedureService`-style Apex class. The REST action
  `executeIntegrationProcedure` only lists procedures with an Agentforce signature, and setting
  `IntegrationProcedureInput`/`Output` through the data API failed with `UNKNOWN_EXCEPTION`.
- **Impact:** procedures cannot be integration-tested from Apex or CI. **Phase 8** (Agentforce, MCP) will need the
  signature: configure it in the designer and retrieve the metadata.

### KI-027 Components deploy inactive; API-activated FlexCards generate no LWC — _Constraint_

- **What happens:** OmniStudio validates references at deploy time, so a Data Mapper cannot be deployed in the same
  pass as the fields it maps, nor an Integration Procedure with the Data Mapper or Apex class it calls (both fail with
  an unhelpful `UNKNOWN_EXCEPTION`). `--profile full` therefore deploys full-profile modules after the active modules,
  in stages (classes + Data Mappers → Integration Procedures → the rest), activating after each stage. A newly
  deployed Data Mapper also arrives inactive although its source says active. The setup script
  activates Data Mappers, Integration Procedures and FlexCards through the data API. Activating a FlexCard that way
  does not generate the `cf<Name>` Lightning web component the designer's Activate button creates, so the page uses
  the standard runtime component `runtime_omnistudio:flexcard` with `flexcardName`. FlexCards created through the
  API get the default author "Vlocity" in their unique name (`FC_CustomerHeader_Vlocity_1`).

### KI-028 `enableOmniStudioMetadata` is irreversible and restricts names — _Constraint_

- **What happens:** OmniStudio components are invisible to the Metadata API until
  `OmniStudioSettings.enableOmniStudioMetadata` is on (set in `project-scratch-def-full.json`). Once on it cannot be
  turned off, and component names must not contain spaces or special characters. The CLI cannot retrieve the
  `OmniStudio` settings at API 62–68 ("unknown"), although deploying them works.
- **Impact:** enabling it in a sandbox or production org is a one-way change: plan it.

### KI-029 Full- and agentforce-profile modules are not deployed or tested in CI — _Open_

- **What happens:** CI Gate 3 builds the headless org. The full-profile modules (20 to 50) and the agentforce-profile
  modules (60, 70) get the static gates only; deploy, Apex tests and drift run manually with `--profile full` (a full
  bootstrap takes ~17 minutes, most of it site deployment) or `--profile agentforce` on DevHubAI (KI-041).
- **Resolution:** CI jobs on the full and agentforce definitions (manual dispatch or nightly, to save scratch-org
  quota; the agentforce job needs a DevHubAI auth URL secret).

## Experience Cloud (Phase 6)

### KI-030 Phase 6 pages not exercised in a browser — _Verify_

- **What happens:** guest record access, the public site's HTTP response, deal registration routing, conversion and
  the channel conflict rule were verified in the org, but nobody has viewed the LWR home page (component placed by
  editing the bundle JSON), the Partner Central flow component, or logged in as the partner.
- **Resolution:** run the README "Click-through checklist" (Phase 6).

### KI-031 Site metadata holds org-specific values — _Constraint_

- **What happens:** retrieved `CustomSite` files name the admin user (`siteAdmin`, `siteGuestRecordDefaultOwner`) and
  `Network` files an email (`emailSenderAddress`, required). Source holds `__NEXUS_SITE_ADMIN__` /
  `__NEXUS_SITE_EMAIL__`, replaced at deploy time from environment variables (`sfdx-project.json` `replacements`; the
  setup script exports them, drift detection defaults them to the target org's admin). A new sender address only
  takes effect after email verification, so the org keeps its own value and drift ignores `emailSenderAddress`.
  The pending address (`newSenderAddress`) is the admin's own email: drift ignores it too, and it must be removed
  from any re-retrieved `Network` file.
- **Impact:** any other deploy of module 30 (CI, sandbox) must export both variables first.

### KI-032 Retrieved site bundles can contain properties the deploy schema rejects — _Constraint_

- **What happens:** the LWR site's `sfdc_cms__site` content retrieved with `geoBotsAllowed`, which the deploy then
  rejected ("additionalProperties ... false"). It was removed from source.
- **Impact:** after editing a site in Experience Builder and re-retrieving it, repeat the cleanup and restore the
  placeholders (KI-031).

### KI-033 Site bundles embed regenerated content Ids — _Constraint_

- **What happens:** LWR style files reference managed content by Id (`sfdc_cms:media.source.ref`), and the platform
  creates new content on every deploy. `digitalExperiences` and `experiences` are therefore advisory in drift
  detection (reported, not failing).

### KI-034 Standard external profiles cannot create users; custom profile permissions ignored — _Constraint_

- **What happens:** creating a user with the standard "Partner Community User" profile fails unless "Allow using
  standard external profiles for self-registration, user creation, and login" is enabled. Nexus uses a custom
  `Nexus Partner User` profile instead (the recommended practice). Object permissions in that profile's metadata
  were ignored on deploy, so Account/Contact read is granted by `PS_Partner_Deal_Registration`.


### KI-036 Guest Apex responses are CDN-cached — _Constraint_

- **What happens:** both sites keep the default `enableApexCDNCaching`, and `PortalContentController` is
  `cacheable=true`, so guest responses can be served from the CDN. An article that is retired (or a draft published
  by mistake and then reverted) can stay visible to guests until the cached response expires.
- **Resolution (if needed):** turn off Apex CDN caching for Nexus Hospitality, or accept the delay for public content.

## CRM Analytics & Multi-Framework (Phase 7)

### KI-037 Phase 7 dashboard and React explorer not exercised in a browser — _Verify_

- **What happens:** the explorer's two GraphQL queries were run against the org as the admin, the analytics app was
  created from the template and its dataset queried with SAQL, and the React app is covered by Vitest. Nobody has
  opened the explorer in Lightning (rendering, SLDS styling hooks, Lightning Web Security) or viewed the dashboard
  (widget layout, faceting).
- **Resolution:** run the README "Click-through checklist" (Phase 7).

### KI-038 UIBundle and WaveTemplateBundle deploy only at API 66.0 — _Constraint_

- **What happens:** at the project's `sourceApiVersion` (62.0) a `UIBundle` deploy fails with "Not available for
  deploy for this API version", and `--api-version` alone does not help because the generated package.xml keeps the
  source version. Modules 40 and 50 are listed in `deployApiVersions`; the setup script deploys them from a manifest
  generated at 66.0 and drift detection retrieves at the highest version in use.
- **Resolution (later):** raise `sourceApiVersion` for the whole project once the other modules are verified at 66.0.

### KI-039 The analytics app is created from the template, not deployed — _Constraint_

- **What happens:** source holds only the `WaveTemplateBundle`; the app, dataset, recipe and dashboard are created
  in each org by `sf analytics app create`. Consequences: drift detection compares the template, not the app; an
  edit made in Analytics Studio is lost on the next org unless the template is recreated and retrieved (README,
  Phase 7); the setup script skips the app when a folder with its name exists, so a changed template needs the app
  deleted (or `sf analytics app update`) in an existing org. A retrieved template must be checked for org Ids and
  usernames before commit; the current one has none. The recipe reads connected objects synced by the Analytics
  Integration User, so new fields need its access and a template update.

## Agentforce, MCP & HXL (Phase 8)

### KI-040 Phase 8 widget rendering and MCP client connection not exercised — _Verify_

- **What happens:** the agent was exercised with `sf agent preview` against live actions (search returned the
  structured payload, booking with confirmation, double booking refused), the widget and types passed the platform's
  deploy-time validation, and the MCP server is active with both tools. Nobody has seen `hotelCard` render in the
  Agentforce panel (including the interpolated texts such as `USD {!$suite.nightlyRate} / night` and the Book button's
  `action/sendMessage`), and no MCP client has connected: the hosted endpoint rejects CLI session tokens and needs an
  External Client App with the `mcp_api` scope (OAuth in a browser).
- **Resolution:** run the README "Click-through checklist" (Phase 8).

### KI-041 Agentforce profile: specific Dev Hub, beta HXL formats, not in CI — _Constraint_

- **What happens:** `--profile agentforce` needs a Dev Hub whose scratch orgs can have `Einstein1AIPlatform` (DevHubAI);
  the free DevHubGS orgs cannot. CI covers the static gates only (as for the full profile, KI-029). HXL is beta and its
  formats were confirmed by deploy-time validation: list attributes need `items`; `tile/icon` names come from a fixed
  set that the error message truncates (the header icon was dropped); the platform drops `"type"` from Custom Lightning
  Type schemas, so source omits it. `BotSettings.enableBots` needs legal-terms acceptance and is not set (employee
  agents do not need it).
- **Impact:** a DevHubAI scratch org is the only place to deploy and test modules 60 and 70.

### KI-042 Agent and MCP activation are org state; re-publishing makes a new version — _Constraint_

- **What happens:** the agent's source is the Agent Script bundle; `sf agent publish authoring-bundle` compiles it into
  `AiAgentDefinition` / `Bot` metadata (not committed) and each publish creates a new agent version. The setup script
  publishes only when the agent does not exist yet, then activates it. MCP servers deploy inactive; the setup script
  creates the `McpServerAccess` record that activates them. After changing the Agent Script on an existing org, run
  `sf agent publish authoring-bundle -n Nexus_Hotel_Concierge` and `sf agent activate` by hand.
