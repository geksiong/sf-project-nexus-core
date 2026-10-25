# Nexus Core Engineering Standard: DevOps, Packaging Strategy & CI/CD Gates

- **Standard Code:** `BP-DEVOPS-008`
- **Module Target:** `scripts/devops/`, `.github/workflows/` (GitHub Actions), `config/devops/nexus-devops.json`, and `sfdx-project.json`
- **Related ADR:** `docs/adr/0005-source-driven-packaging-strategy.md`

---

## 1. Dual-Loop Packaging & Deployment Model

Nexus Core operates on a **Hybrid Packaging Model** that separates local development / AI assistant feedback loops from formal production distribution:

```text
 ┌────────────────────────────────────────────────────────┐
 │           INNER LOOP (Development & AI Agents)         │
 │  - Multiple Package Directories (MPD) in modules/      │
 │  - Fast source deployments (sf project deploy start)    │
 │  - 5-10s feedback cycle; 0 Dev Hub build quota used   │
 └──────────────────────────┬─────────────────────────────┘
                            │
                            ▼ On Git Tag (vX.Y.Z)
 ┌────────────────────────────────────────────────────────┐
 │           OUTER LOOP (Release & Distribution)          │
 │  - 2GP Unlocked Packages (sf package version create)   │
 │  - Immutable versioned 04t artifacts                   │
 │  - Automated dependency verification via sfdx-project  │
 └────────────────────────────────────────────────────────┘
```

### 1.1 Why Not 2GP for Local Development?
- **Build Times:** Compiling a 2GP package version (`04t`) requires 5 to 20 minutes on Salesforce servers per iteration.
- **Dev Hub Quotas:** Free Developer Edition Dev Hubs enforce strict daily package version creation limits (max 6/day).
- **AI Velocity:** AI coding agents stall if forced through asynchronous packaging queues.

---

## 2. CI/CD Quality Gates & Pull Request Validations
Every pull request is validated by `.github/workflows/ci.yml` against three progressive gates. All of them except the
scratch org suite also run locally with `npm run verify`.

1. **Static Analysis & Schema Validation** (job `Gate 1 - Static analysis & schemas`):
   - `npm run format:check` / `npm run lint` / `npm run test:unit`: Prettier (Apex, LWC, JSON, YAML), ESLint (`@salesforce/eslint-config-lwc`) and LWC Jest.
   - `npm run lint:apex`: Salesforce Code Analyzer (PMD Recommended + the Nexus ruleset `config/pmd/nexus-apex-rules.xml`), failing on High/Critical. Nexus rules enforce `WITH USER_MODE`, SOQL only in `*Selector` classes, no dynamic SOQL outside selectors, one-line triggers, and the invocable result envelope.
   - `npm run test:pmd-rules`: regression fixtures (`config/pmd/fixtures/`) prove every Nexus rule still fires, without false positives.
   - `npm run validate:clt`: Custom Lightning Type, HXL widget and MCP server definition contracts (schemas, `$ref`s, renderer and composition bindings).
2. **Orphaned Metadata & Module Boundaries** (same job) and **Drift** (nightly):
   - `npm run audit:metadata` (`scripts/devops/audit-orphaned-metadata.sh`): blocks Apex entry points / custom fields / custom permissions without permission set grants, and unreferenced tabs, LWCs, screen flows, Apex, widgets, Custom Lightning Types and VIPs.
   - `npm run audit:deps` (`scripts/devops/generate-dependency-graph.js`): builds the module graph from source references and enforces downward-only layering, declared dependencies, and complete 2GP transitive dependency chains.
   - `scripts/devops/drift-detect.sh` (`.github/workflows/nightly-drift.yml`): retrieves the active modules from a long-lived org and compares them semantically with `main`.
3. **Automated Scratch Org Test Suite** (job `Gate 3 - Scratch org test suite`, ready PRs and manual runs):
   - Provisions an ephemeral scratch org with `scripts/org-init/setup-scratch-headless.sh` (headless definition, Nebula Logger, deploy, PSG assignment, personas, `data/data-plan.json`).
   - `scripts/devops/run-apex-tests.sh` runs every Nexus test class and requires $\ge 85\%$ coverage of Nexus classes.
   - Deletes the scratch org.

Active modules, the coverage threshold, external package symbols and the reasoned allowlist live in
`config/devops/nexus-devops.json`. See `docs/devops/github-setup.md` for repository secrets and branch protection.
