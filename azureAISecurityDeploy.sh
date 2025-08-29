
#!/bin/bash
set -e

# azureAISecurityDeploy.sh
# Usage: ./azureAISecurityDeploy.sh [RESOURCE_GROUP_NAME]
echo "version 2.9"

# Try to resolve resource group automatically if not provided
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.azd_state.env"

detect_rg() {
    local rg=""
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        if [ -n "${AZD_WORKDIR:-}" ] && [ -d "${AZD_WORKDIR}" ]; then
            if [ -n "${AZD_ENV:-}" ]; then
                rg=$(cd "$AZD_WORKDIR" && azd env get-values -e "$AZD_ENV" | sed -n 's/^AZURE_RESOURCE_GROUP=//p' | tr -d '\r')
            else
                rg=$(cd "$AZD_WORKDIR" && azd env get-values | sed -n 's/^AZURE_RESOURCE_GROUP=//p' | tr -d '\r')
            fi
        fi
    fi
    echo "$rg"
}

RESOURCE_GROUP="${1:-}"
if [ -z "$RESOURCE_GROUP" ]; then
    RESOURCE_GROUP=$(detect_rg)
fi
if [ -z "$RESOURCE_GROUP" ]; then
    read -r -p "Enter the resource group name to secure: " RESOURCE_GROUP
fi

# Subscription ID used for subscription-scope checks and ARM calls
SUBSCRIPTION_ID=$(az account show --query id -o tsv)


# Find the Log Analytics workspace in the resource group
LOG_ANALYTICS_WS_ID=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.OperationalInsights/workspaces" --query "[0].id" -o tsv)
if [ -z "$LOG_ANALYTICS_WS_ID" ]; then
    echo "No Log Analytics workspace found in resource group $RESOURCE_GROUP. Defender for AI cannot be enabled."
    exit 1
fi



# Check subscription-wide Defender for AI plan; skip workspace wiring if already enabled
AI_SUB_STATUS="unknown"
AI_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/AI?api-version=2024-01-01"
AI_JSON=$(az rest --method GET --url "$AI_URL" --only-show-errors 2>/dev/null || true)
if echo "$AI_JSON" | grep -q '"pricingTier"\s*:\s*"Standard"'; then
    AI_SUB_STATUS="already enabled"
    AI_PLAN_ENABLED=1
else
    AI_SUB_STATUS="not enabled"
    AI_PLAN_ENABLED=0
fi

# Enable Defender for AI on OpenAI resources (only if not already enabled at subscription)
OPENAI_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.CognitiveServices/accounts" --query "[?kind=='OpenAI'].name" -o tsv)
OPENAI_STATUS="➖"
if [ "$AI_PLAN_ENABLED" -eq 1 ]; then
    OPENAI_STATUS="✅ (subscription)"
else
for openai in $OPENAI_RESOURCES; do
    echo "Checking Defender for AI on OpenAI resource: $openai"
    current_ws=$(az security workspace-setting list --query "[?name=='default'].workspaceId" -o tsv)
    if [ "$current_ws" = "$LOG_ANALYTICS_WS_ID" ]; then
        echo "Defender for AI already enabled for $openai."
        OPENAI_STATUS="✅"
    else
        echo "Enabling Defender for AI on OpenAI resource: $openai"
        if az security workspace-setting create --name "default" --target-workspace "$LOG_ANALYTICS_WS_ID"; then
            OPENAI_STATUS="✅"
        else
            OPENAI_STATUS="❌"
        fi
    fi
done
fi
# Check subscription-wide Defender for Storage plan; skip per-account if already enabled
STORAGE_SUB_STATUS="unknown"
STG_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/StorageAccounts?api-version=2024-01-01"
STG_JSON=$(az rest --method GET --url "$STG_URL" --only-show-errors 2>/dev/null || true)
if echo "$STG_JSON" | grep -q '"pricingTier"\s*:\s*"Standard"'; then
    STORAGE_SUB_STATUS="already enabled"
    STORAGE_PLAN_ENABLED=1
else
    STORAGE_SUB_STATUS="not enabled"
    STORAGE_PLAN_ENABLED=0
fi

# Enable Defender for Storage at the storage account level using ARM API (only if not subscription-wide enabled)
STORAGE_ACCOUNTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Storage/storageAccounts" --query "[].name" -o tsv)
declare -A STORAGE_RESULTS
if [ "${STORAGE_PLAN_ENABLED:-0}" -eq 1 ]; then
    STORAGE_SUB_MARK="✅"
else
    for sa in $STORAGE_ACCOUNTS; do
        echo "Enabling Defender for Storage (with advanced settings) on account: $sa"
        url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${sa}/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-01-01"
        body='{ "properties": { "isEnabled": true, "overrideSubscriptionLevelSettings": true, "malwareScanning": { "onUpload": { "isEnabled": true } }, "sensitiveDataDiscovery": { "isEnabled": true } } }'
        if az rest --method PUT --url "$url" --body "$body" --headers "Content-Type=application/json"; then
            STORAGE_RESULTS[$sa]="✅"
        else
            echo "Failed to enable Defender for Storage on $sa."
            STORAGE_RESULTS[$sa]="❌"
        fi
    done
fi


# Summary of protections
echo
echo "Security Protections Summary:"
echo "- Defender for AI (subscription): $( [ "$AI_PLAN_ENABLED" -eq 1 ] && echo "✅ already enabled" || echo "❌ not enabled" )"
echo "- Defender for AI (OpenAI): $OPENAI_STATUS"
if [ "${STORAGE_PLAN_ENABLED:-0}" -eq 1 ]; then
    echo "- Defender for Storage (subscription): ✅ already enabled"
else
    echo "- Defender for Storage (per account):"
    for sa in ${!STORAGE_RESULTS[@]}; do
        echo "    - $sa: ${STORAGE_RESULTS[$sa]}"
    done
fi

# Optional: subscription-wide Defender plans with prompt and state tracking
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.defender_state.env"
YELLOW='\033[1;33m'; NC='\033[0m'

# Check AppServices plan status at subscription scope
APPSVC_SUB_STATUS="skipped"
APPSVC_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/AppServices?api-version=2024-01-01"
APPSVC_JSON=$(az rest --method GET --url "$APPSVC_URL" --only-show-errors 2>/dev/null || true)
if echo "$APPSVC_JSON" | grep -q '"pricingTier"\s*:\s*"Standard"'; then
    APPSVC_SUB_STATUS="already enabled"
else
    echo -e "${YELLOW}Warning:${NC} Defender for App Services is not enabled at subscription scope. This plan cannot be scoped to resource group."
    read -r -p "Enable Defender for App Services subscription-wide now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        body='{ "properties": { "pricingTier": "Standard" } }'
        if az rest --method PUT --url "$APPSVC_URL" --body "$body" --headers "Content-Type=application/json"; then
            APPSVC_SUB_STATUS="enabled now"
            APPSERVICES_CHANGED=1
        else
            APPSVC_SUB_STATUS="failed"
        fi
    fi
fi

# Check CosmosDbs plan status at subscription scope
COSMOS_SUB_STATUS="skipped"
COSMOS_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/CosmosDbs?api-version=2024-01-01"
COSMOS_JSON=$(az rest --method GET --url "$COSMOS_URL" --only-show-errors 2>/dev/null || true)
if echo "$COSMOS_JSON" | grep -q '"pricingTier"\s*:\s*"Standard"'; then
    COSMOS_SUB_STATUS="already enabled"
else
    echo -e "${YELLOW}Warning:${NC} Defender for Cosmos DB is not enabled at subscription scope. This plan cannot be scoped to resource group."
    read -r -p "Enable Defender for Cosmos DB subscription-wide now? [y/N] " ans2
    if [[ "$ans2" =~ ^[Yy]$ ]]; then
        body='{ "properties": { "pricingTier": "Standard" } }'
        if az rest --method PUT --url "$COSMOS_URL" --body "$body" --headers "Content-Type=application/json"; then
            COSMOS_SUB_STATUS="enabled now"
            COSMOSDBS_CHANGED=1
        else
            COSMOS_SUB_STATUS="failed"
        fi
    fi
fi

# Persist state so cleanup can optionally revert
APPSERVICES_CHANGED=${APPSERVICES_CHANGED:-0}
COSMOSDBS_CHANGED=${COSMOSDBS_CHANGED:-0}
if [ "$APPSERVICES_CHANGED" = "1" ] || [ "$COSMOSDBS_CHANGED" = "1" ]; then
    {
        echo "# Auto-generated by azureAISecurityDeploy.sh"
        echo "SUBSCRIPTION_ID=\"$SUBSCRIPTION_ID\""
        echo "APPSERVICES_CHANGED=\"$APPSERVICES_CHANGED\""
        echo "COSMOSDBS_CHANGED=\"$COSMOSDBS_CHANGED\""
    } > "$STATE_FILE"
    echo "Recorded subscription-wide Defender changes to $STATE_FILE"
fi

APPSVC_MARK="➖"; [ "$APPSVC_SUB_STATUS" = "already enabled" ] && APPSVC_MARK="✅"; [ "$APPSVC_SUB_STATUS" = "enabled now" ] && APPSVC_MARK="✅"; [ "$APPSVC_SUB_STATUS" = "failed" ] && APPSVC_MARK="❌"
COSMOS_MARK="➖"; [ "$COSMOS_SUB_STATUS" = "already enabled" ] && COSMOS_MARK="✅"; [ "$COSMOS_SUB_STATUS" = "enabled now" ] && COSMOS_MARK="✅"; [ "$COSMOS_SUB_STATUS" = "failed" ] && COSMOS_MARK="❌"
echo "- Defender plan (App Services) at subscription: $APPSVC_MARK $APPSVC_SUB_STATUS"
echo "- Defender plan (Cosmos DBs) at subscription: $COSMOS_MARK $COSMOS_SUB_STATUS"

echo
echo "All specified security features have been attempted for resources in $RESOURCE_GROUP."
