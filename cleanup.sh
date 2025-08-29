
#!/bin/bash
set -e

# cleanup.sh
# Usage: ./cleanup.sh <RESOURCE_GROUP_NAME>

if [ -z "$1" ]; then
    echo "Usage: $0 <RESOURCE_GROUP_NAME>"
    exit 1
fi

RESOURCE_GROUP="$1"

echo "Starting cleanup of security configurations in resource group: $RESOURCE_GROUP"


# Disable Defender for AI workspace-setting (applies to all OpenAI resources in the workspace)
echo "Disabling Defender for AI workspace-setting (default) in this subscription..."
az security workspace-setting delete --name "default" || true

# Disable Defender for Storage at the storage account level using ARM API
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
STORAGE_ACCOUNTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Storage/storageAccounts" --query "[].name" -o tsv)
for sa in $STORAGE_ACCOUNTS; do
    echo "Disabling Defender for Storage on account: $sa"
    url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${sa}/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-01-01"
    body='{ "properties": { "isEnabled": false, "overrideSubscriptionLevelSettings": true, "malwareScanning": { "onUpload": { "isEnabled": false } }, "sensitiveDataDiscovery": { "isEnabled": false } } }'
    az rest --method PUT --url "$url" --body "$body" --headers "Content-Type=application/json" || true
done

echo "Security configurations successfully removed!"

# Optionally revert subscription-wide Defender plan changes recorded by deploy script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.defender_state.env"
YELLOW='\033[1;33m'; NC='\033[0m'
if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    if [ "${APPSERVICES_CHANGED:-0}" = "1" ] || [ "${COSMOSDBS_CHANGED:-0}" = "1" ]; then
        echo -e "${YELLOW}Warning:${NC} Subscription-wide Defender plans were enabled by the deploy script."
        read -r -p "Do you want to revert these subscription-wide changes now? [y/N] " revert
        if [[ "$revert" =~ ^[Yy]$ ]]; then
            if [ "${APPSERVICES_CHANGED:-0}" = "1" ]; then
                echo "Reverting Defender plan for App Services at subscription scope..."
                url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/AppServices?api-version=2024-01-01"
                body='{ "properties": { "pricingTier": "Free" } }'
                az rest --method PUT --url "$url" --body "$body" --headers "Content-Type=application/json" || true
            fi
            if [ "${COSMOSDBS_CHANGED:-0}" = "1" ]; then
                echo "Reverting Defender plan for Cosmos DBs at subscription scope..."
                url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/CosmosDbs?api-version=2024-01-01"
                body='{ "properties": { "pricingTier": "Free" } }'
                az rest --method PUT --url "$url" --body "$body" --headers "Content-Type=application/json" || true
            fi
            echo "Revert complete."
            rm -f "$STATE_FILE" || true
        else
            echo "Leaving subscription-wide Defender plans as-is. You can re-run cleanup later to revert."
        fi
    fi
fi

# Optionally, clean up all resources if azd was used
# Prefer using the azd workdir/env captured by the bootstrap to target the correct project
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZD_STATE_FILE="$SCRIPT_DIR/.azd_state.env"
if [ -f "$AZD_STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$AZD_STATE_FILE"
    if [ -n "${AZD_WORKDIR:-}" ] && [ -d "$AZD_WORKDIR" ]; then
        echo "Running 'azd down --force --purge' in $AZD_WORKDIR ..."
        if [ -n "${AZD_ENV:-}" ]; then
            (cd "$AZD_WORKDIR" && azd down --force --purge -e "$AZD_ENV") || true
        else
            (cd "$AZD_WORKDIR" && azd down --force --purge) || true
        fi
    else
        echo "(Info) No recorded azd workdir found; attempting azd down in current directory."
        azd down --force --purge || true
    fi
else
    echo "(Info) No .azd_state.env present; attempting azd down in current directory."
    azd down --force --purge || true
fi

# Remove Azure Front Door profile created by the secure step (no prompt)
PROFILE_NAME="fd-${RESOURCE_GROUP}"
ID=$(az resource show -g "$RESOURCE_GROUP" -n "$PROFILE_NAME" --resource-type Microsoft.Cdn/profiles --query id -o tsv 2>/dev/null || true)
if [ -z "$ID" ]; then
    echo "No Front Door profile '$PROFILE_NAME' found in RG '$RESOURCE_GROUP'. Skipping."
else
    echo "Deleting Front Door profile '$PROFILE_NAME'..."
    az resource delete --ids "$ID" --only-show-errors || true
    echo "Front Door removal complete."
fi

echo "Cleanup complete!"
