# Implementation Plan: Nexus Core Modular Reference Implementation

## Overview
A 17-week, 8-phase delivery roadmap designed for iterative implementation using an AI coding assistant. Standard Developer Edition Dev Hubs and scratch orgs are used for Phases 1 through 7, deferring Agentforce/HXL trial dependencies to Phase 8.

---

## 1. Timeline & Milestone Overview

```text
Week:   1   2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17
Phase 1: Foundation, Admin Cockpit & Sales Engine [===]
Phase 2: DevOps, CI/CD & Auditing                     [==]
Phase 3: Service Desk & Entitlements                      [==]
Phase 4: CapEx Engine & Event-Bus                             [==]
Phase 5: OmniStudio Service Facade                                [==]
Phase 6: Dual Experience Cloud (LWR & Aura)                           [==]
Phase 7: CRMA & Multi-Framework React                                     [==]
Phase 8: Agentforce, MCP & HXL Stack                                           [==]
```

---

## 2. Detailed Phase Breakdown

### Phase 1: Foundation Scaffold, Admin Cockpit & Demo App 1 (Sales Engine) (Weeks 1–3)
- **Target Env:** Standard Developer Edition Dev Hub + `config/project-scratch-def-headless.json`.
- **Deliverables:**
  - Setup `00-foundation`: `TriggerHandler.cls`, `OrgLimitsService.cls`, `adminLimitsCockpit` LWC, `BypassService.cls`, `TestDataFactory.cls`, Nebula Logger.
  - Setup `data/`: `data-plan.json`, `accounts.json`, `opportunities.json` for automated seed loading.
  - Setup `10-core-domain/sales-engine`:
    - `OpportunityTrigger.trigger` routing to `OpportunityTriggerHandler.cls`.
    - `OpportunitiesSelector.cls` (enforcing `WITH USER_MODE`, line items, and contact roles).
    - `OpportunityService.cls` (validations and stage progression logic).
    - `PSG_Sales_Representative` Permission Set Group.
    - Opportunity Guided Deal Closer Screen Flow & Multi-Tier Discount Approvals.
    - Sales Performance Joined Report (Pipeline vs. Won Revenue) and Dashboard.
- **DoD:** Scratch org provisions in < 2 mins; data imports cleanly via `sf data import tree`; Admin Cockpit LWC renders live limits; unit tests achieve >= 85% coverage in < 15s.

### Phase 2: DevOps, Quality Auditing & Drift Pipeline (Weeks 4–5)
- **Target Env:** CI/CD runners (GitLab CI / GitHub Actions).
- **Deliverables:** Automated linting, PMD `WITH USER_MODE` rules, orphaned metadata scanner, nightly drift detection.

### Phase 3: Demo App 2 (Omni-Channel Service Desk, Case Teams & Entitlements) (Weeks 6–7)
- **Target Env:** Standard Developer Edition Dev Hub + `config/project-scratch-def-headless.json`.
- **Deliverables:** `CaseTrigger.trigger`, `CaseTriggerHandler.cls`, Entitlement Process & SLA Milestones, Omni-Channel Queues, `CasesSelector.cls`, `CaseEscalationService.cls`, `CaseTeamMember` dynamic provisioning, `PSG_Service_Agent`.

### Phase 4: Demo App 3 (Back-Office CapEx Engine & Platform Events) (Weeks 8–9)
- **Target Env:** Standard Developer Edition Dev Hub + `config/project-scratch-def-headless.json`.
- **Deliverables:** `CapEx_Request__c` (Private OWD), `CapEx_Approved__e` Platform Event, asynchronous Ledger consumer, Named Credentials (`Mock_ERP_Ledger`).

### Phase 5: Demo App 4 (OmniStudio Service Facade & Service 360) (Weeks 10–11)
- **Target Env:** Scratch org with `"features": ["OmniStudioDesigner", "OmniStudioRuntime"]`.
- **Deliverables:** Data Mappers, `VIP_Customer360` Integration Procedure, `FC_CustomerHeader` FlexCard without direct SOQL.

### Phase 6: Dual Experience Cloud: LWR Guest Portal & Aura Partner Central (Weeks 12–13)
- **Target Env:** Scratch org with `"features": ["Communities", "Sites"]`.
- **Deliverables:** LWR Hospitality Site (`DigitalExperienceBundle`), Light-DOM LWCs, Aura Partner Central (`ExperienceBundle`), Deal Registration submission form & channel approval routing.

### Phase 7: Demo Apps 7 & 8 (CRM Analytics & Multi-Framework React) (Weeks 14–15)
- **Target Env:** Scratch org with `"features": ["AnalyticsAdminPerms", "DevelopmentWave"]` and Multi-Framework enabled.
- **Deliverables:** CRMA Data Prep recipes, decoupled `template-info.json` dashboard packaging, React 18+ Asset Explorer `UIBundle` under LWS.

### Phase 8: Demo App 9 (Autonomous Agentforce, MCP & HXL UI Stack) (Weeks 16–17)
- **Target Env:** Agentforce Developer Trial Org, Partner Business Org (PBO), or Enterprise Sandbox.
- **Deliverables:** `HotelSearchAction.cls`, Custom Lightning Types, HXL `UiWidgetBundle` (`hotelCard`), `hotelMcp.mcpServerDefinition-meta.xml`.