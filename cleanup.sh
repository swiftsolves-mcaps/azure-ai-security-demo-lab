
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

# Optional: Revoke Entra ID (Microsoft Entra) app client secrets used for App Service auth
# This will NOT delete the app registrations; it only removes existing password credentials (client secrets).
# We'll attempt to detect candidate app IDs from azd environment values and from each Web App's auth settings.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZD_STATE_FILE="$SCRIPT_DIR/.azd_state.env"

detect_app_ids() {
    local ids=""
    # 1) From azd env values (common variable names)
    if [ -f "$AZD_STATE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$AZD_STATE_FILE"
        if [ -n "${AZD_WORKDIR:-}" ] && [ -d "$AZD_WORKDIR" ]; then
            local ENV_CONTENT
            if [ -n "${AZD_ENV:-}" ]; then
                ENV_CONTENT=$(cd "$AZD_WORKDIR" && azd env get-values -e "$AZD_ENV" | tr -d '\r' || true)
            else
                ENV_CONTENT=$(cd "$AZD_WORKDIR" && azd env get-values | tr -d '\r' || true)
            fi
            if [ -n "$ENV_CONTENT" ]; then
                # Candidate keys seen across samples
                for key in AAD_CLIENT_ID WEB_AUTH_AAD_CLIENT_ID APP_REG_CLIENT_ID FRONTEND_CLIENT_ID AZURE_CLIENT_ID; do
                    local val
                    val=$(echo "$ENV_CONTENT" | sed -n "s/^${key}=//p" | head -n1)
                    if echo "$val" | grep -Eq '^[0-9a-fA-F-]{36}$'; then
                        ids="$ids $val"
                    fi
                done
            fi
        fi
    fi
    # 2) From App Service auth settings in this resource group
    local apps
    apps=$(az webapp list -g "$RESOURCE_GROUP" --query "[?contains(kind, 'function')==\`false\`].name" -o tsv | tr -d '\r' || true)
    if [ -n "$apps" ]; then
        while IFS= read -r app; do
            [ -z "$app" ] && continue
            local cid
            cid=$(az webapp auth show -g "$RESOURCE_GROUP" -n "$app" --query "identityProviders.azureActiveDirectory.registration.clientId" -o tsv 2>/dev/null | tr -d '\r' || true)
            if echo "$cid" | grep -Eq '^[0-9a-fA-F-]{36}$'; then
                # de-dup
                if ! echo "$ids" | grep -qw "$cid"; then
                    ids="$ids $cid"
                fi
            fi
        done <<< "$apps"
    fi
    echo "$ids" | tr ' ' '\n' | sed '/^$/d' | sort -u
}

APP_IDS=$(detect_app_ids)
if [ -n "$APP_IDS" ]; then
    echo
    echo "Detected Entra app IDs that may have client secrets used for this demo:"
    echo "$APP_IDS" | nl -w2 -s') '
    read -r -p "Do you want to delete ALL client secrets for these app registrations now? [y/N] " delsecrets
    if [[ "$delsecrets" =~ ^[Yy]$ ]]; then
        while IFS= read -r appId; do
            [ -z "$appId" ] && continue
            echo "Listing client secrets for app: $appId"
            keyIds=$(az ad app show --id "$appId" --query "passwordCredentials[].keyId" -o tsv 2>/dev/null || true)
            if [ -z "$keyIds" ]; then
                echo "  (none found or insufficient permissions)"
                continue
            fi
            while IFS= read -r k; do
                [ -z "$k" ] && continue
                echo "  Deleting secret keyId=$k"
                az ad app credential delete --id "$appId" --key-id "$k" 1>/dev/null 2>&1 || echo "    (failed or already removed)"
            done <<< "$keyIds"
        done <<< "$APP_IDS"
        echo "Client secret cleanup complete."
    else
        echo "Skipped Entra client secret cleanup."
    fi
else
    echo "No candidate Entra app registrations detected for client secret cleanup."
fi
