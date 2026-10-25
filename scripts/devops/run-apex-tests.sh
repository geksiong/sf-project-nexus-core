#!/usr/bin/env bash
#
# Runs every Nexus Core Apex test class in the active modules and enforces the coverage gate.
# RunLocalTests is avoided on purpose: it would also run ~1,300 tests from the unlocked Nebula Logger package.
#
# Usage: scripts/devops/run-apex-tests.sh --target-org <alias> [--profile headless|full] [--output-dir test-results]
#                                        [--min-coverage 85]
set -euo pipefail

TARGET_ORG=""
OUTPUT_DIR="test-results"
PROFILE="headless"
MIN_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-org|-o) TARGET_ORG="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --min-coverage) MIN_ARGS=(--min "$2"); shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done
[[ -n "$TARGET_ORG" ]] || { echo "--target-org is required" >&2; exit 1; }

cd "$(dirname "$0")/../.."
mapfile -t MODULES < <(jq -r --arg p "$PROFILE" '(.activeModules + (if $p == "full" then .fullProfileModules // [] else [] end))[]' config/devops/nexus-devops.json)
TEST_ARGS=()
while IFS= read -r test_class; do
    TEST_ARGS+=(-n "$test_class")
done < <(find "${MODULES[@]}" -name '*Test.cls' -exec basename {} .cls \; | sort)

mkdir -p "$OUTPUT_DIR"
echo "Running $(( ${#TEST_ARGS[@]} / 2 )) Nexus test classes against $TARGET_ORG..."
sf apex run test -o "$TARGET_ORG" "${TEST_ARGS[@]}" -c -w 30 -r json -d "$OUTPUT_DIR" --json > "$OUTPUT_DIR/test-result.json" || true
node scripts/devops/check-apex-coverage.js "$OUTPUT_DIR/test-result.json" "${MIN_ARGS[@]}"
