#!/usr/bin/env bash
# Orphaned metadata & missing permission audit for the active modules.
set -euo pipefail
cd "$(dirname "$0")/../.."
exec node scripts/devops/audit-orphaned-metadata.js "$@"
