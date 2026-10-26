# ADR 0007: Agentforce Agent, Hosted MCP Server and HXL Widgets over One Action Layer

* **Status:** Accepted
* **Deciders:** Enterprise Architecture Lead & Platform Engineers
* **Date:** 2026-10-26 (Phase 8)

## Context and Problem Statement
Demo App 9 (Hotel Concierge) serves three conversational surfaces: an Agentforce employee agent in Lightning, external
AI clients (Claude, ChatGPT) over the Model Context Protocol, and rich in-conversation UI on both through the Headless
Experience Layer (HXL, beta). Each surface has its own metadata (Agent Script, McpServerDefinition, UiWidgetBundle,
LightningTypeBundle) and they must not fork the business logic, the access model or the rendering.

## Decision Drivers
* One implementation of search and booking, with the same rules whoever calls it.
* Results render as the same widget in Agentforce and in MCP clients.
* Everything deploys from source into an Agentforce scratch org; no Setup clicks beyond what the platform cannot
  express as metadata.
* The static gates must catch broken links between the parts (types, widgets, tools, Apex) before deployment.

## Considered Options
1. **Separate implementations per surface** (Flow for the agent, Apex REST for MCP).
2. **One invocable action layer shared by all surfaces**, with the HXL widget and Custom Lightning Types as the shared
   rendering contract.

## Decision
Option 2.

* **Actions:** `HotelSearchAction` and `BookHotelSuiteAction` keep the result envelope and delegate to
  `HotelConciergeService`. They are `global` (hosted MCP tools) and return top-level `global` payload classes with
  `@JsonAccess` and `@AuraEnabled` fields, the only shape Custom Lightning Types can reference
  (`@apexClassType/c__HotelSearchPayload`).
* **Rules:** bookings are private, but availability and pricing must not depend on who asks (employee, agent, MCP
  client), so the `Suite_Booking__c` trigger evaluates them through `HotelBookingFactsSelector` (system mode,
  AGENTS.md 2.1). Searches read suites in user mode; inserts run in user mode.
* **Rendering:** one widget (`hotelCard`, module 60) bound by two renderers: `hotelSearchResponse` for the agent's
  action output and the MCP wrapper `hotelSearchResult` (over `hotelSearchOutputValues`) for MCP clients.
* **Agent:** Agent Script (`AiAuthoringBundle`) is the source. Its action outputs declare the CLT
  (`complex_data_type_name`), which replaces the Setup "Show in conversation / Output Rendering" step. The generated
  agent definition is not committed; the setup script publishes and activates the agent.
* **MCP:** `McpServerDefinition` tools point at the actions through the API Catalog (`aa:apex-<Class>`); the search tool
  names the widget resource (`ui://widget/lightningType/c__hotelSearchResult`). Activation (`McpServerAccess`) and
  client OAuth (External Client App) are org configuration, done by the setup script and by hand respectively.
* **Org shape:** a third setup profile, `agentforce` (`config/project-scratch-def-agentforce.json`: Einstein platform,
  Agent Platform, HXL), on a Dev Hub entitled to Agentforce scratch orgs. Modules 60 and 70 deploy at API 67.0.

## Consequences
* **Positive:** one tested service behind three surfaces; one widget; the contract validator checks widget bindings,
  type references (including Apex fields), renderers, MCP tools and agent action targets.
* **Negative:** HXL is beta and partly undocumented (formats were confirmed against deploy-time validation); the
  agentforce profile needs a specific Dev Hub and is not in CI; `global` classes cannot later be removed from a managed
  package.
* **Operational:** widget rendering and MCP client connections can only be verified interactively (README checklist,
  KI-040). Re-publishing an agent creates a new version (KI-042).
