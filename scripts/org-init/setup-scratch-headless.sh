#!/usr/bin/env bash
#
# Provisions a Nexus Core scratch org end to end. Profiles (config/devops/nexus-devops.json):
#   headless (default, CI): Phases 1-4 on config/project-scratch-def-headless.json
#   full: adds fullProfileModules (Phase 5+ OmniStudio, ...) on config/project-scratch-def-full.json
#   create org -> install Nebula Logger -> deploy modules -> permissions -> persona users -> seed data -> tests
#
# Usage: scripts/org-init/setup-scratch-headless.sh [--alias nexus-dev] [--dev-hub DevHubGS] [--days 7]
#                                                   [--profile headless|full] [--skip-create] [--skip-tests]
#
# Scratch Developer Edition orgs include only 2 Salesforce licenses, so the admin user doubles as the
# Sales Representative and Service Agent personas, and one extra "Sales Manager" user is created to
# approve Tier 1 discounts.
set -euo pipefail

ALIAS="nexus-dev"
DEV_HUB=""
DAYS=7
SKIP_CREATE=false
SKIP_TESTS=false
PROFILE="headless"
NEBULA_LOGGER_PACKAGE_ID="04tg7000000IzRdAAK" # Nebula Logger - Core@4.19.5 (unlocked)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --alias) ALIAS="$2"; shift 2 ;;
        --dev-hub) DEV_HUB="$2"; shift 2 ;;
        --days) DAYS="$2"; shift 2 ;;
        --skip-create) SKIP_CREATE=true; shift ;;
        --skip-tests) SKIP_TESTS=true; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
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
    sf_json org create scratch -f "config/project-scratch-def-$PROFILE.json" -a "$ALIAS" -y "$DAYS" \
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

# Active modules come from config/devops/nexus-devops.json (shared with CI and the audit gates).
mapfile -t MODULES < <(jq -r '.activeModules[]' config/devops/nexus-devops.json)
FULL_MODULES=()
[[ "$PROFILE" == "full" ]] && mapfile -t FULL_MODULES < <(jq -r '(.fullProfileModules // [])[]' config/devops/nexus-devops.json)
DEPLOY_ARGS=()
for module in "${MODULES[@]}"; do DEPLOY_ARGS+=(-d "$module"); done
# A Case assignment rule cannot reference a queue created in the same deployment, so queues (and the
# roles and routing configs they reference) go first.
step "Pre-deploying service desk queues"
sf_json project deploy start -o "$ALIAS" -m Role -m QueueRoutingConfig -m Queue --wait 30 \
    | jq -r '"    \(.result.numberComponentsDeployed) components deployed"'

step "Deploying ${MODULES[*]}"
# An entitlement process that entitlements already use cannot be redeployed, even unchanged ("Cannot update
# SLA process that is in use"); changes need a new process version. On re-runs, deploy everything else.
if [[ -n "$(query_id "SELECT Id FROM SlaProcess WHERE Name = 'Nexus Standard Support'")" ]]; then
    MANIFEST_DIR=$(mktemp -d)
    MANIFEST_ARGS=()
    for module in "${MODULES[@]}"; do MANIFEST_ARGS+=(--source-dir "$module"); done
    sf_json project generate manifest "${MANIFEST_ARGS[@]}" --output-dir "$MANIFEST_DIR" --name package.xml >/dev/null
    perl -0pi -e 's{<types>(?:(?!</types>).)*?<name>EntitlementProcess</name>\s*</types>\s*}{}s' "$MANIFEST_DIR/package.xml"
    echo "    Nexus Standard Support is in use - skipping EntitlementProcess (see docs/known-issues.md)"
    DEPLOY_ARGS=(--manifest "$MANIFEST_DIR/package.xml")
fi
sf_json project deploy start -o "$ALIAS" "${DEPLOY_ARGS[@]}" --wait 30 \
    | jq -r '"    \(.result.numberComponentsDeployed) components deployed"'

# Full-profile modules deploy after the active modules, in stages: OmniStudio validates references at deploy
# time, so a Data Mapper cannot be created with the fields it maps, nor an Integration Procedure with the Data
# Mapper or Apex class it calls. Each stage is activated before the next (deployed components can arrive
# inactive; activation through the data API matches the designers' Activate button).
activate_omnistudio() {
    local body object id
    body=$(mktemp)
    echo '{"IsActive":true}' > "$body"
    for spec in "OmniDataTransform:" "OmniProcess: AND IsIntegrationProcedure = true" "OmniUiCard:"; do
        object="${spec%%:*}"
        for id in $(sf_json data query -o "$ALIAS" -q "SELECT Id FROM $object WHERE IsActive = false${spec#*:}" \
            | jq -r '.result.records[].Id'); do
            sf api request rest "/services/data/v62.0/sobjects/$object/$id" -o "$ALIAS" --method PATCH \
                --body "@$body" >/dev/null
            echo "    Activated $object $id"
        done
    done
}
for module in "${FULL_MODULES[@]}"; do
    step "Deploying $module (full profile)"
    for stage in "classes omniDataTransforms" "omniIntegrationProcedures" ""; do
        STAGE_ARGS=()
        if [[ -z "$stage" ]]; then
            STAGE_ARGS=(-d "$module")
        else
            for type_dir in $stage; do
                while IFS= read -r dir; do STAGE_ARGS+=(-d "$dir"); done < <(find "$module" -type d -name "$type_dir")
            done
        fi
        [[ ${#STAGE_ARGS[@]} -eq 0 ]] && continue
        sf_json project deploy start -o "$ALIAS" "${STAGE_ARGS[@]}" --wait 30 \
            | jq -r --arg s "${stage:-remaining metadata}" '"    \($s): \(.result.numberComponentsDeployed) components deployed"'
        activate_omnistudio
    done
done

step "Assigning admin permission sets"
ADMIN_ID=$(sf_json org display user -o "$ALIAS" | jq -r '.result.id')
PERMSETS=(PS_Nexus_Admin PS_Sales_Admin LoggerAdmin PS_CapEx_Submitter PS_CapEx_Admin)
[[ "$PROFILE" == "full" ]] && PERMSETS+=(PS_Customer360_User)
for permset in "${PERMSETS[@]}"; do
    if [[ -z "$(query_id "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '$ADMIN_ID' AND PermissionSet.Name = '$permset'")" ]]; then
        sf_json org assign permset -o "$ALIAS" -n "$permset" >/dev/null
    fi
done

# There is no `sf org assign permsetgroup`: wait for the group to finish calculating, then insert the assignment.
assign_psg() {
    local psg psg_id
    for _ in $(seq 1 30); do
        psg=$(sf_json data query -o "$ALIAS" -q "SELECT Id, Status FROM PermissionSetGroup WHERE DeveloperName = '$1'")
        [[ "$(jq -r '.result.records[0].Status' <<<"$psg")" == "Updated" ]] && break
        sleep 5
    done
    psg_id=$(jq -r '.result.records[0].Id' <<<"$psg")
    if [[ -z "$(query_id "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '$ADMIN_ID' AND PermissionSetGroupId = '$psg_id'")" ]]; then
        sf_json data create record -o "$ALIAS" -s PermissionSetAssignment \
            -v "AssigneeId=$ADMIN_ID PermissionSetGroupId=$psg_id" >/dev/null
    fi
}

step "Assigning PSG_Sales_Representative and PSG_Service_Agent"
assign_psg PSG_Sales_Representative
assign_psg PSG_Service_Agent

# Org data the service desk needs that the Metadata API cannot deploy.
step "Configuring service desk (case team roles, Omni-Channel presence, queue membership)"
for role in "Technical SME:Edit" "Escalating Agent:Edit" "Account Manager:Read"; do
    if [[ -z "$(query_id "SELECT Id FROM CaseTeamRole WHERE Name = '${role%%:*}'")" ]]; then
        sf_json data create record -o "$ALIAS" -s CaseTeamRole -v "Name='${role%%:*}' AccessLevel=${role##*:}" >/dev/null
    fi
done
# Presence status access is not supported in PermissionSet metadata (API 62): grant it to PS_Omni_Channel_Agent.
OMNI_PS_ID=$(query_id "SELECT Id FROM PermissionSet WHERE Name = 'PS_Omni_Channel_Agent'")
STATUS_ID=$(query_id "SELECT Id FROM ServicePresenceStatus WHERE DeveloperName = 'Available_Cases'")
if [[ -z "$(query_id "SELECT Id FROM SetupEntityAccess WHERE ParentId = '$OMNI_PS_ID' AND SetupEntityId = '$STATUS_ID'")" ]]; then
    sf_json data create record -o "$ALIAS" -s SetupEntityAccess -v "ParentId=$OMNI_PS_ID SetupEntityId=$STATUS_ID" >/dev/null
fi
# Queues admit Service_Agent role members; the admin holds the Sales Representative role, so add it directly.
for queue in Tier_1_Support Tier_2_Technical_Escalations; do
    QUEUE_ID=$(query_id "SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = '$queue'")
    if [[ -z "$(query_id "SELECT Id FROM GroupMember WHERE GroupId = '$QUEUE_ID' AND UserOrGroupId = '$ADMIN_ID'")" ]]; then
        sf_json data create record -o "$ALIAS" -s GroupMember -v "GroupId=$QUEUE_ID UserOrGroupId=$ADMIN_ID" >/dev/null
    fi
done
echo "    Case team roles, Available - Cases presence status and Tier 1/Tier 2 queue membership ready"

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
REVIEWER_PS_ID=$(query_id "SELECT Id FROM PermissionSet WHERE Name = 'PS_CapEx_Reviewer'")
if [[ -z "$(query_id "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '$MANAGER_ID' AND PermissionSetId = '$REVIEWER_PS_ID'")" ]]; then
    sf_json data create record -o "$ALIAS" -s PermissionSetAssignment \
        -v "AssigneeId=$MANAGER_ID PermissionSetId=$REVIEWER_PS_ID" >/dev/null
fi
echo "    Sales Manager approves the admin's CapEx requests (PS_CapEx_Reviewer)"

step "Seeding sample data"
if [[ -z "$(query_id "SELECT Id FROM Opportunity WHERE Name = 'Acme Industrial IoT Expansion'")" ]]; then
    sf_json data import tree -o "$ALIAS" --plan data/data-plan.json | jq -r '"    \(.result | length) records imported"'
else
    echo "    Seed data already present - skipped"
fi
sf_json apex run -o "$ALIAS" -f scripts/org-init/seed-service-desk.apex \
    | jq -r '.result.logs' | grep -oE 'USER_DEBUG\|[^|]*\|DEBUG\|.*' | cut -d'|' -f4 | sed 's/^/    Service desk: /'
sf_json apex run -o "$ALIAS" -f scripts/org-init/seed-capex.apex \
    | jq -r '.result.logs' | grep -oE 'USER_DEBUG\|[^|]*\|DEBUG\|.*' | cut -d'|' -f4 | sed 's/^/    CapEx: /'

if [[ "$SKIP_TESTS" == false ]]; then
    step "Running Nexus Core Apex tests (coverage gate)"
    scripts/devops/run-apex-tests.sh --target-org "$ALIAS" --profile "$PROFILE" --output-dir "test-results/$ALIAS"
fi

step "Done in $(( $(date +%s) - START ))s"
echo "    Admin Cockpit: sf org open -o $ALIAS -p lightning/n/Nexus_Admin_Cockpit"
echo "    Sales app:     sf org open -o $ALIAS -p lightning/app/c__Nexus_Sales"
echo "    Service app:   sf org open -o $ALIAS -p lightning/app/c__Nexus_Service"
echo "    Operations:    sf org open -o $ALIAS -p lightning/app/c__Nexus_Operations"
[[ "$PROFILE" == "full" ]] && echo "    Customer 360:  sf org open -o $ALIAS -p lightning/app/c__Nexus_Customer_360"
