# Product Requirements Document (PRD)
**Product Name:** Salesforce Modular Enterprise Reference Platform ("Nexus Core")  
**Target Audience:** Enterprise Salesforce Architects, Platform Engineers, Delivery Leads, Developers & AI Coding Assistants  
**Status:** Approved for Implementation  

---

## 1. Executive Summary & Vision

### 1.1 Vision
To deliver a turnkey, composable, production-ready Salesforce reference implementation demonstrating gold-standard architectural patterns across:
- **Core CRM Platform:** Sales Cloud (`Account`, `Contact`, `Opportunity`, `OpportunityLineItem`) and Service Cloud (`Case`, `CaseTeamMember`, Omni-Channel routing, Entitlements & SLA Milestones).
- **Enterprise Apex & Security:** Pragmatic Clean Architecture (Base TriggerHandler, Domain Services, User-Mode Selectors), Event-Driven Architecture (EDA), Private OWD, `WITH USER_MODE`, and Trigger Bypass orchestration.
- **Admin Cockpit & Observability:** Real-time `/limits` health telemetry via `System.OrgLimits`, threshold alerts, and centralized Nebula Logger error monitoring.
- **Declarative Governance:** Permission Set Groups (PSGs), automated data seeding plans.
- **Data Fabric & Facades:** OmniStudio Integration Procedures (VIPs) and Data Mappers.
- **Experience Cloud Dual Runtimes:**
  - **LWR Runtime:** High-performance public hospitality portal with CMS content publication approvals.
  - **Aura Runtime (Partner Central):** Authenticated B2B partner portal with Deal Registration approvals and external role-hierarchy sharing.
- **Analytics & Modern Runtimes:** CRM Analytics decoupled templates and Multi-Framework React 18+ micro-frontends (`UIBundle`) under LWS.
- **Agentic & Protocol Capabilities:** Headless Invocable Actions, Custom Lightning Types, declarative HXL UI Widget Bundles, and Model Context Protocol (MCP) Server Definitions.

---

## 2. Documented User, Role, and Permission Model
Detailed in `docs/salesforce_org_and_licensing_advisory.md`.

### 2.1 Internal Role Hierarchy & Personas
- **User 1 (`System Admin / Exec`):** Executive VP / CRO. Deploys metadata, executes Tier-2 approvals.
- **User 2 (`Sales & Ops Rep`):** Account Executive & CapEx Submitter. Runs Deal Closer Screen Flow.
- **User 3 (`Sales / Channel Manager`):** Line manager. Approves Tier-1 discounts, CapEx, and Partner Deal Registrations.
- **User 4 (`Service Agent & SME`):** Frontline support agent. Omni-Channel queue handling, Case Team SME.

### 2.2 External Partner Role & Persona
- **User 5 (`B2B Partner Rep`):** External partner user (`Partner Community` License). Logs into Aura Partner Central and registers deals.

### 2.3 Permission Set Groups (PSGs)
- `PSG_Sales_Representative`: Bundles `PS_Sales_Rep` and object permissions.
- `PSG_Service_Agent`: Bundles `PS_Service_Agent` and Omni-Channel permissions.

---

## 3. Package & Directory Structure

```text
nexus-core/
├── .gitlab-ci.yml
├── sfdx-project.json
├── package.json
├── AGENTS.md
├── config/
│   ├── project-scratch-def-headless.json
│   └── project-scratch-def-full.json
├── data/
│   ├── data-plan.json
│   ├── accounts.json
│   └── opportunities.json
├── scripts/
│   ├── devops/
│   │   ├── audit-orphaned-metadata.sh
│   │   ├── drift-detect.sh
│   │   ├── generate-dependency-graph.js
│   │   └── validate-clt-schemas.js
│   └── org-init/
│       ├── setup-scratch-headless.sh
│       └── setup-scratch-full.sh
└── modules/
    ├── 00-foundation/
    │   ├── admin-cockpit/                  # LWC adminLimitsCockpit & OrgLimitsService
    │   ├── bypass-framework/               # BypassService.cls
    │   ├── trigger-framework/              # TriggerHandler.cls base class
    │   ├── logger/
    │   ├── test-framework/
    │   └── named-credentials/
    ├── 10-core-domain/
    │   ├── sales-engine/                   # Demo App 1: Opps, Screen Flows, PSGs, TriggerHandlers
    │   ├── service-desk/                   # Demo App 2: Cases, Omni-Channel, Case Teams, SLA
    │   ├── capex-operations/               # Demo App 3: CapEx_Request__c, Platform Events
    │   ├── reports/
    │   └── dashboards/
    ├── 20-omnistudio/
    ├── 30-experience-cloud/
    ├── 40-crm-analytics/
    ├── 50-multi-framework/
    ├── 60-hxl-widgets/
    └── 70-agentforce-mcp/
```

---

## 4. Concrete Reference Demonstration Applications

### 4.1 Demo App 1: Enterprise Sales & Pipeline Engine (Phase 1)
*Demonstrates: `Account`, `Contact`, `Opportunity`, `OpportunityLineItem`, Clean Architecture (Service + Selector + TriggerHandler), Deal Closer Screen Flow, Multi-tier Discount Approvals, and Pipeline Joined Reports.*

### 4.2 Demo App 2: Omni-Channel Service Desk & SLA Escalation Engine (Phase 3)
*Demonstrates: `Case`, `CaseTeamMember`, `CaseTeamRole`, Omni-Channel Queues, Routing Configurations, Entitlements & SLA Milestones, Clean Architecture Cases Service, and Automated Incident Escalation Flows.*

### 4.3 Demo App 3: Back-Office CapEx & Operations Engine (Phase 4)
*Demonstrates: `CapEx_Request__c`, `Ledger_Entry__c`, Event-Driven Architecture (`CapEx_Approved__e`), Private OWD, Criteria-Based Sharing, Named Credentials.*

### 4.4 Demo App 4: Service 360 & Operations Intelligence (Phase 5)
*Demonstrates: OmniStudio VIP (Integration Procedure) + Data Mappers + FlexCards + Nebula Logger.*

### 4.5 Demo App 5: Experience Cloud LWR Guest Portal & Content Approval (Phase 6)
*Demonstrates: Experience Cloud LWR + DigitalExperienceBundle + Custom CMS/Knowledge Approval Flow to Live Site.*

### 4.6 Demo App 6: Experience Cloud Aura B2B Partner Central & Deal Registration (Phase 6)
*Demonstrates: Experience Cloud Aura Runtime (`ExperienceBundle`) + Partner Community Licensing + Deal Registration + Partner Role Hierarchy Sharing.*

### 4.7 Demo App 7: Executive Analytics Intelligence (Phase 7)
*Demonstrates: CRM Analytics Data Prep Recipes + Decoupled App Templates (`template-info.json`).*

### 4.8 Demo App 8: Multi-Framework React Account & Asset Explorer (Phase 7)
*Demonstrates: Salesforce Multi-Framework (`UIBundle`) + React 18+ (TSX) + GraphQL Wire Service + LWS + SLDS Tokens.*

### 4.9 Demo App 9: Autonomous Hotel Concierge & Booking Service (Phase 8)
*Demonstrates: Agentforce Topic + MCP Server + Invocable Apex + Custom Lightning Types + HXL UiWidgetBundle.*