# ADR 0006: Decoupled Analytics Templates and Multi-Framework UI Bundles

* **Status:** Accepted
* **Deciders:** Enterprise Architecture Lead & Platform Engineers
* **Date:** 2026-10-26 (Phase 7)

## Context and Problem Statement
Phase 7 adds two runtimes outside the Apex/LWC stack: CRM Analytics (Demo App 7) and a React micro-frontend
(Demo App 8). Both must deploy from source into a fresh scratch org with no manual Studio or builder steps, stay
reviewable in git, and respect the module boundaries and access model of the rest of the platform.

## Decision Drivers
* Fresh full-profile orgs must come up complete from `setup-scratch-headless.sh --profile full`.
* CRM Analytics assets (datasets, recipe runs, dashboards) bind to org Ids that change in every org.
* A React app must read Salesforce data under the running user's permissions, without custom Apex endpoints.
* Build output must be reproducible and tested before it deploys.

## Considered Options
**Analytics:**
1. Deploy the app's assets directly (`WaveApplication`, `WaveRecipe`, `WaveDataset`, `WaveDashboard`).
2. **Deploy a `WaveTemplateBundle` and create the app from it** (decoupled template packaging).

**React:**
1. A React app inside an LWC (static resource, `lwc:dom="manual"`).
2. **A `UIBundle` (Salesforce Multi-Framework)** built with Vite, reading data through UI API GraphQL.

## Decision
**Analytics: option 2.** `modules/40-crm-analytics` holds only the template (`template-info.json`, the R3 recipe,
the dashboard JSON, dataset XMD, variables and rules). The setup script deploys it and runs
`sf analytics app create --templatename` for each entry in `nexus-devops.json` `analyticsTemplates`, which creates
the dataset, syncs the connected objects (Opportunity, Account), runs the recipe (`executeCondition:
CreateSyncExecute`) and creates the dashboard, all bound to the new org's Ids. The template is the unit of change: edit
the app in Analytics Studio, recreate the template from it, retrieve, review.

**React: option 2.** `NexusAssetExplorer` is a React 19 + TypeScript `UIBundle`. Data comes from
`@salesforce/platform-sdk` GraphQL (UI API), so object and field access are the user's own and the bundle needs no
Apex; `PS_Asset_Explorer_User` grants what it reads. Styling uses SLDS global styling hooks (`--slds-g-*`) with
fallbacks. `npm run test:ui-bundles` (in `verify` and CI) runs Vitest, the type check and the Vite build; only `dist/`
and the bundle metadata deploy.

Both metadata types need API 66.0, above the project's `sourceApiVersion`; such modules are listed in
`deployApiVersions` and deploy from a manifest generated at that version (drift retrieves at the highest version in
use).

## Consequences
* **Positive:** no org Ids in source; a fresh org gets a working app and dataset in one step; the React app inherits
  the platform's security model and theming; both are covered by the static gates.
* **Negative:** Analytics edits round-trip through Studio and template recreation rather than direct source edits;
  template changes do not update an app created earlier (the setup script skips an existing app). The React bundle
  adds an npm toolchain and a build step to the gates.
* **Operational:** neither runtime can be exercised headlessly beyond its data layer (GraphQL queries, SAQL on the
  dataset); the browser checks are in the README checklist (KI-037).
