# Known Issues & Platform Constraints

Open findings from code reviews and platform constraints discovered during implementation. Each entry says what
happens, why it matters, and the proposed resolution. When an entry is resolved, delete it and mention the ID in the
commit message.

**Status:** _Decision_ = needs a product/owner decision before work starts; _Open_ = agreed, not yet done;
_Constraint_ = platform limitation with a workaround in place; _Verify_ = suspected, needs a manual check.

| ID     | Area         | Status     | Summary                                                                 |
| ------ | ------------ | ---------- | ----------------------------------------------------------------------- |
| KI-001 | Service desk | Decision   | Two paths skip the escalation policy                                    |
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
| KI-018 | Agentforce   | Open       | Phase 8 scaffold: CLT renderer binds fields the schema does not expose  |
| KI-020 | CapEx        | Constraint | Criteria-based sharing cannot be asserted in Apex tests                 |
| KI-021 | Reporting    | Constraint | Joined report on the CapEx custom report type is rejected ("Obsolete")  |
| KI-022 | CapEx        | Constraint | ERP integration is simulated; named credential is the legacy format     |
| KI-023 | CapEx        | Open       | CapEx status can be set directly by administrators                      |
| KI-024 | CapEx        | Verify     | One unreproduced posting-test failure on the first run after deploy     |

---

## Service desk (Phase 3)

### KI-001 Two paths skip the escalation policy — _Decision_

- **What happens:** the escalation policy (High priority, Tier 2 queue, timestamp, comment, case team) runs only on
  update. (a) A case _inserted_ with `Status = Escalated` (data import, integration) is not routed or prioritised.
  (b) An agent can set a **closed** case straight to `Escalated`, which reopens it without the checks that
  `EscalateCaseAction` applies (the action rejects closed cases with `INVALID_STATE`).
- **Decision needed:** should an escalated status on insert apply the full policy? Should closed → Escalated be
  blocked (validation in `CaseEscalationService.applyEscalationPolicy`), or allowed as a deliberate reopen?
- **Where:** `CaseEscalationService.applyEscalationPolicy`, `CaseTriggerHandler.beforeInsert`.

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

## Later-phase scaffolding

### KI-018 Phase 8: CLT renderer binds fields the schema does not expose — _Open_

- **What happens:** `70-agentforce-mcp/custom-lightning-types/hotelInfoResult/renderer.json` binds
  `$payload.hotelDetails.*`, but the result schema exposes `outputValues`. Allowlisted (`clt-renderer-binding`) in
  `config/devops/nexus-devops.json`.
- **Resolution:** fix the binding when Phase 8 starts and remove the allowlist entry.

## Back-office CapEx (Phase 4)

### KI-020 Criteria-based sharing cannot be asserted in Apex tests — _Constraint_

- **What happens:** the platform writes criteria-based share rows when the transaction commits. Apex test
  transactions never commit (`Test.stopTest()` does not flush them), so the positive case of **Approved CapEx to
  Finance** cannot be asserted. `CapExLifecycleIntegrationTest` covers the hierarchy, peers and "no access before
  approval"; the rule itself was verified in a scratch org (an approved request gets a `Rule` share, Read, to the
  Finance Controller role group).
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
- **Resolution:** a validation rule allowing status changes only from the approval process (or a bypass custom
  permission for data migration).

### KI-024 One unreproduced posting-test failure on the first run after deploy — _Verify_

- **What happens:** the very first run of the CapEx tests after the classes were first deployed failed
  `approvalPublishesAnEventThatPostsToTheLedger` and `opsAdminRequeuesAFailedPosting`: the ledger entry stayed
  Pending with no error, as if the posting job never ran. Every later run passed (five runs, including one with the
  admin's CapEx permission sets removed), so it is not a permission dependency. A fresh-org bootstrap (first run after deploy) also passed.
- **Resolution:** watch CI. If it recurs, capture the debug log of the event delivery and the job.
