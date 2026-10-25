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