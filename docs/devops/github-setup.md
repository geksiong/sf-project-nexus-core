# GitHub Setup: CI, Drift Detection & Branch Protection

Nexus Core's pipelines are GitHub Actions workflows:

| Workflow | Trigger | Jobs |
| --- | --- | --- |
| `.github/workflows/ci.yml` | PRs to `main`, pushes to `main`, manual | **Gate 1 - Static analysis & schemas** (always), **Gate 3 - Scratch org test suite** (ready PRs and manual runs) |
| `.github/workflows/nightly-drift.yml` | Daily 18:00 UTC (02:00 SGT), manual | **Drift against target org** |

Both org-dependent jobs skip with a warning until their secrets exist, so the first push is safe.

## 1. First push

```bash
git remote add origin git@github.com:<owner>/sf-project-nexus-core.git
git push -u origin main
git push -u origin feature/phase-1-foundation-sales-engine feature/phase-2-devops
```

Open PRs in order (Phase 1 into `main`, then Phase 2) so each runs the gates.

## 2. Repository secrets

Secrets are sfdx auth URLs (`force://...`). They grant full access to the org: store them only as encrypted
repository secrets, never in files or logs.

| Secret | Used by | Org |
| --- | --- | --- |
| `SF_DEVHUB_AUTH_URL` | Gate 3 | Dev Hub that creates scratch orgs (`DevHubGS`) |
| `SF_TARGET_ORG_AUTH_URL` | Nightly drift | Long-lived org deployed from `main` (integration sandbox, or a Developer Edition org) |

```bash
# Requires the GitHub CLI (gh auth login) - the auth URL never touches disk
sf org display --target-org DevHubGS --verbose --json | jq -r '.result.sfdxAuthUrl' | gh secret set SF_DEVHUB_AUTH_URL
sf org display --target-org <target-org-alias> --verbose --json | jq -r '.result.sfdxAuthUrl' | gh secret set SF_TARGET_ORG_AUTH_URL
```

The auth URL is only present for orgs authorized with a refresh token (`sf org login web`). For CI, prefer a dedicated
integration user over a personal login.

Scratch orgs expire (max 30 days), so they are a poor drift target. Use an org you deploy `main` to.

## 3. Branch protection for `main`

Settings -> Branches -> Add rule for `main`:

- Require a pull request before merging.
- Require status checks: `Gate 1 - Static analysis & schemas` and `Gate 3 - Scratch org test suite`.
- Require branches to be up to date before merging.

## 4. Dev Hub quota

Free Developer Edition Dev Hubs allow **6 scratch orgs per day and 3 active**. Gate 3 therefore runs only on PRs that
are marked ready for review (not drafts) and on manual dispatch, cancels superseded runs, and always deletes its org.
Keep work-in-progress PRs as drafts. Check the remaining quota with:

```bash
sf org list limits --target-org DevHubGS | grep -i scratch
```

## 5. Running the gates locally

```bash
npm ci
npm run verify                                              # Gate 1 and the audits
scripts/org-init/setup-scratch-headless.sh --dev-hub DevHubGS # Gate 3 equivalent (includes Apex tests)
scripts/devops/drift-detect.sh --target-org nexus-dev       # drift against any org
```

`npm run verify` needs Java 11+ and the Code Analyzer plugin: `sf plugins install code-analyzer`.
