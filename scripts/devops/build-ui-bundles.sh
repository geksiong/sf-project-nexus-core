#!/usr/bin/env bash
#
# Installs, tests (Vitest) and builds every Multi-Framework UI bundle (modules/**/uiBundles/<name>).
# The build (tsc type-check + vite build) writes dist/, which is what deploys; dist/ is not committed.
#
# Usage: scripts/devops/build-ui-bundles.sh [--skip-tests]
set -euo pipefail
cd "$(dirname "$0")/../.."
SKIP_TESTS=false
[[ "${1:-}" == "--skip-tests" ]] && SKIP_TESTS=true

mapfile -t BUNDLES < <(find modules -path '*/uiBundles/*/package.json' -not -path '*/node_modules/*' -exec dirname {} \; | sort)
[[ ${#BUNDLES[@]} -eq 0 ]] && { echo "No UI bundles."; exit 0; }
for bundle in "${BUNDLES[@]}"; do
    echo "==> $bundle"
    if [[ ! -d "$bundle/node_modules" ]]; then
        npm --prefix "$bundle" ci --no-audit --no-fund --loglevel=error
    fi
    if [[ "$SKIP_TESTS" == false ]]; then
        (cd "$bundle" && npx vitest run --reporter=dot)
    fi
    npm --prefix "$bundle" run build --silent
done
echo "UI bundles OK: ${#BUNDLES[@]}"
