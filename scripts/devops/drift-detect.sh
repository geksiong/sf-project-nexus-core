#!/usr/bin/env bash
# Nightly drift detection: compares the active modules in git with a target org.
# Usage: scripts/devops/drift-detect.sh --target-org <alias> [--report drift-report.md]
set -euo pipefail
cd "$(dirname "$0")/../.."
exec node scripts/devops/drift-detect.js "$@"
