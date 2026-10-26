#!/usr/bin/env bash
# PMD gate: Salesforce Code Analyzer with the PMD Recommended rules plus the Nexus custom ruleset
# (code-analyzer.yml), over the active modules. Fails on any High (2) or Critical (1) violation.
set -euo pipefail
cd "$(dirname "$0")/../.."
ARGS=()
while IFS= read -r module; do ARGS+=(--workspace "$module"); done < <(jq -r '(.activeModules + [to_entries[] | select(.key | endswith("ProfileModules")) | .value[]]) | unique[]' config/devops/nexus-devops.json)
exec sf code-analyzer run "${ARGS[@]}" --rule-selector pmd:Recommended --rule-selector pmd:Custom \
    --severity-threshold 2 --view table "$@"
