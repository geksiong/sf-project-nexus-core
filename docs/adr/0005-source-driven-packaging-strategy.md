# ADR 0005: Source-Driven Modular Packaging Strategy (Inner vs. Outer Loop)

* **Status:** Accepted
* **Deciders:** Enterprise Architecture Lead, DevOps Team
* **Date:** 2026-10-22

## Context and Problem Statement
Nexus Core adopts a modular architecture structured across 8 package directories in `modules/`. In Salesforce DX, teams can deploy code either via:
1. **Source-Driven Deployments:** Deploying raw metadata directly to scratch orgs (`sf project deploy start --source-dir modules/<name>`).
2. **Package-Versioned Artifacts (2GP):** Compiling metadata into versioned Unlocked Packages (`sf package version create` -> install `04t...`).

We need a clear strategy that supports rapid local development and AI coding assistants while preserving enterprise packaging boundaries for release.

## Decision Drivers
* **Inner Loop Velocity:** AI coding agents and developers need immediate feedback loops (5–10 seconds), whereas building 2GP versions takes 5–20 minutes per package.
* **Developer Edition Dev Hub Limits:** Free Dev Hub orgs have strict daily/hourly limits on package version creations (often max 6 per day).
* **Metadata Compatibility:** Bleeding-edge metadata (Agentforce, HXL UiWidgetBundle, DigitalExperienceBundle) faces packaging dependency blockers that do not affect source deployments.

## Decision Outcome
Adopt a **Hybrid Packaging Strategy**:
1. **Inner Loop (Development, Scratch Orgs, CI PR Checks, AI Agents):**
   - Treat `modules/` as **Multiple Package Directories (MPD)**.
   - Deploy raw source directly via `sf project deploy start --source-dir modules/<name>`.
   - Validate module boundaries using automated dependency graph linters (`audit-orphaned-metadata.sh`, `generate-dependency-graph.js`).
2. **Outer Loop (Release & Tagged Distribution):**
   - Use the dependency declarations in `sfdx-project.json` to generate immutable 2GP unlocked packages only upon release tagging (`vX.Y.Z`) for deployment to upper sandbox environments and production.

### Positive Consequences
* Instant feedback loop for AI assistants and developers.
* Zero consumption of Dev Hub daily package version limits during sprint cycles.
* The codebase remains 100% 2GP-compliant from day one because boundaries and dependencies are maintained in `sfdx-project.json`.