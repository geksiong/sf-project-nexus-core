#!/usr/bin/env bash
#
# Provisions a Nexus Core headless scratch org (Phases 1-4) end to end:
#   create org -> install Nebula Logger -> deploy modules -> permissions -> persona users -> seed data -> tests
#
# Usage: scripts/org-init/setup-scratch-headless.sh [--alias nexus-dev] [--dev-hub DevHubGS] [--days 7]
#                                                   [--skip-create] [--skip-tests]
#
# Scratch Developer Edition orgs include only 2 Salesforce licenses, so the admin user doubles as the
# Sales Representative persona and one extra "Sales Manager" user is created to approve Tier 1 discounts.
set -euo pipefail

ALIAS="nexus-dev"
DEV_HUB=""
DAYS=7
SKIP_CREATE=false
SKIP_TESTS=false
NEBULA_LOGGER_PACKAGE_ID="04tg7000000IzRdAAK" # Nebula Logger - Core@4.19.5 (unlocked)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --alias) ALIAS="$2"; shift 2 ;;
        --dev-hub) DEV_HUB="$2"; shift 2 ;;
        --days) DAYS="$2"; shift 2 ;;
        --skip-create) SKIP_CREATE=true; shift ;;
        --skip-tests) SKIP_TESTS=true; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

cd "$(dirname "$0")/../.."
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

START=$(date +%s)
step() { printf '\n\033[1;34m==> %s\033[0m (+%ss)\n' "$1" "$(( $(date +%s) - START ))"; }

# Runs an sf command with --json and fails with the CLI's message when status != 0.
sf_json() {
    local out
    out=$(sf "$@" --json 2>/dev/null) || true
    if [[ "$(jq -r '.status' <<<"$out")" != "0" ]]; then
        echo "sf $1 $2 failed: $(jq -r '.message // .' <<<"$out")" >&2
        jq -r '.result.details.componentFailures // empty | if type=="object" then [.] else . end | .[] | "  \(.componentType) \(.fullName): \(.problem)"' <<<"$out" >&2 || true
        exit 1
    fi
    printf '%s' "$out"
}

query_id() {
    sf_json data query -o "$ALIAS" -q "$1" | jq -r '.result.records[0].Id // empty'
}

if [[ "$SKIP_CREATE" == false ]]; then
    step "Creating scratch org '$ALIAS' (${DAYS} days)"
    sf_json org create scratch -f config/project-scratch-def-headless.json -a "$ALIAS" -y "$DAYS" \
        --set-default --wait 15 ${DEV_HUB:+--target-dev-hub "$DEV_HUB"} | jq -r '"    \(.result.username)"'
fi

step "Installing Nebula Logger ($NEBULA_LOGGER_PACKAGE_ID)"
if sf_json package installed list -o "$ALIAS" | jq -e --arg id "$NEBULA_LOGGER_PACKAGE_ID" \
    '.result[] | select(.SubscriberPackageVersionId == $id)' >/dev/null; then
    echo "    Already installed - skipped"
else
    sf_json package install -o "$ALIAS" --package "$NEBULA_LOGGER_PACKAGE_ID" --security-type AdminsOnly \
        --wait 20 --no-prompt >/dev/null
fi

step "Deploying 00-foundation and 10-core-domain"
sf_json project deploy start -o "$ALIAS" -d modules/00-foundation -d modules/10-core-domain --wait 30 \
    | jq -r '"    \(.result.numberComponentsDeployed) components deployed"'

step "Assigning admin permission sets"
ADMIN_ID=$(sf_json org display user -o "$ALIAS" | jq -r '.result.id')
for permset in PS_Nexus_Admin PS_Sales_Admin LoggerAdmin; do
    if [[ -z "$(query_id "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '$ADMIN_ID' AND PermissionSet.Name = '$permset'")" ]]; then
        sf_json org assign permset -o "$ALIAS" -n "$permset" >/dev/null
    fi
done

step "Assigning PSG_Sales_Representative"
for _ in $(seq 1 30); do
    PSG=$(sf_json data query -o "$ALIAS" -q "SELECT Id, Status FROM PermissionSetGroup WHERE DeveloperName = 'PSG_Sales_Representative'")
    [[ "$(jq -r '.result.records[0].Status' <<<"$PSG")" == "Updated" ]] && break
    sleep 5
done
PSG_ID=$(jq -r '.result.records[0].Id' <<<"$PSG")
if [[ -z "$(query_id "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '$ADMIN_ID' AND PermissionSetGroupId = '$PSG_ID'")" ]]; then
    sf_json data create record -o "$ALIAS" -s PermissionSetAssignment \
        -v "AssigneeId=$ADMIN_ID PermissionSetGroupId=$PSG_ID" >/dev/null
fi

step "Creating Sales Manager persona and manager chain"
MANAGER_ID=$(query_id "SELECT Id FROM User WHERE Alias = 'smgr' AND IsActive = true")
if [[ -z "$MANAGER_ID" ]]; then
    MANAGER_ID=$(sf_json org create user -o "$ALIAS" -f config/users/sales-manager-user-def.json \
        "Username=sales.manager.$(date +%s)@nexuscore.dev" | jq -r '.result.fields.id')
fi
REP_ROLE_ID=$(query_id "SELECT Id FROM UserRole WHERE DeveloperName = 'Sales_Representative'")
MANAGER_ROLE_ID=$(query_id "SELECT Id FROM UserRole WHERE DeveloperName = 'Sales_Manager'")
sf_json data update record -o "$ALIAS" -s User -i "$MANAGER_ID" -v "UserRoleId=$MANAGER_ROLE_ID" >/dev/null
sf_json data update record -o "$ALIAS" -s User -i "$ADMIN_ID" -v "UserRoleId=$REP_ROLE_ID ManagerId=$MANAGER_ID" >/dev/null
echo "    Admin (Sales Rep persona) now reports to Sales Manager $MANAGER_ID"

step "Seeding sample data"
if [[ -z "$(query_id "SELECT Id FROM Opportunity WHERE Name = 'Acme Industrial IoT Expansion'")" ]]; then
    sf_json data import tree -o "$ALIAS" --plan data/data-plan.json | jq -r '"    \(.result | length) records imported"'
else
    echo "    Seed data already present - skipped"
fi

if [[ "$SKIP_TESTS" == false ]]; then
    # Nexus test classes only: RunLocalTests would also run ~1,300 tests from the unlocked Nebula Logger package.
    step "Running Nexus Core Apex tests"
    TEST_ARGS=()
    for test_class in $(find modules -name '*Test.cls' -exec basename {} .cls \; | sort); do
        TEST_ARGS+=(-n "$test_class")
    done
    sf apex run test -o "$ALIAS" "${TEST_ARGS[@]}" -c -r human -w 20
fi

step "Done in $(( $(date +%s) - START ))s"
echo "    Admin Cockpit: sf org open -o $ALIAS -p lightning/n/Nexus_Admin_Cockpit"
echo "    Sales app:     sf org open -o $ALIAS -p lightning/app/c__Nexus_Sales"
