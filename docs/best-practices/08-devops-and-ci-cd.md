# Nexus Core Engineering Standard: DevOps, Packaging Strategy & CI/CD Gates

- **Standard Code:** `BP-DEVOPS-008`
- **Module Target:** `scripts/devops/`, `.gitlab-ci.yml`, and `sfdx-project.json`
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

## 2. CI/CD Quality Gates & Merge Request Validations
Every pull request is automatically validated against three progressive gates:
1. **Static Analysis & Schema Validation (`npm test`):**
   - PMD Apex analysis enforcing `WITH USER_MODE` on all SOQL queries.
   - ESLint and Prettier formatting checks.
   - `scripts/devops/validate-clt-schemas.js`: Verifies Custom Lightning Types and HXL widget schemas.
2. **Orphaned Metadata & Drift Scan:**
   - `scripts/devops/audit-orphaned-metadata.sh`: Blocks unused VIPs, unreferenced widgets, or missing permissions.
   - `scripts/devops/drift-detect.sh`: Nightly verification against base branch.
3. **Automated Scratch Org Test Suite:**
   - Spins up an ephemeral scratch org (`config/project-scratch-def-headless.json`).
   - Deploys source, assigns Permission Set Groups (`PSG_Sales_Representative`), and seeds test data (`data/data-plan.json`).
   - Executes Apex unit tests in-memory, requiring $\ge 85\%$ branch coverage.