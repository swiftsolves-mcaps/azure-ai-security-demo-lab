
#!/bin/bash
set -e

# azureAISecurityDeploy.sh
# Usage: ./azureAISecurityDeploy.sh <RESOURCE_GROUP_NAME>
echo "version 1.9"

if [ -z "$1" ]; then
    echo "Usage: $0 <RESOURCE_GROUP_NAME>"
    exit 1
fi

RESOURCE_GROUP="$1"


# Find the Log Analytics workspace in the resource group
LOG_ANALYTICS_WS_ID=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.OperationalInsights/workspaces" --query "[0].id" -o tsv)
if [ -z "$LOG_ANALYTICS_WS_ID" ]; then
    echo "No Log Analytics workspace found in resource group $RESOURCE_GROUP. Defender for AI cannot be enabled."
    exit 1
fi



# Enable Defender for AI on OpenAI resources
OPENAI_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.CognitiveServices/accounts" --query "[?kind=='OpenAI'].name" -o tsv)
for openai in $OPENAI_RESOURCES; do
    echo "Checking Defender for AI on OpenAI resource: $openai"
    current_ws=$(az security workspace-setting list --query "[?name=='default'].workspaceId" -o tsv)
    if [ "$current_ws" = "$LOG_ANALYTICS_WS_ID" ]; then
        echo "Defender for AI already enabled for $openai."
    else
        echo "Enabling Defender for AI on OpenAI resource: $openai"
        az security workspace-setting create --name "default" --target-workspace "$LOG_ANALYTICS_WS_ID"
    fi
done








# Enable Defender for Storage at the storage account level using ARM API
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
STORAGE_ACCOUNTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Storage/storageAccounts" --query "[].name" -o tsv)
declare -A STORAGE_RESULTS
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


# Summary of protections
echo
echo "Security Protections Summary:"
OPENAI_STATUS="✅"
echo "- Defender for AI (OpenAI): $OPENAI_STATUS"
echo "- Defender for Storage:"
for sa in ${!STORAGE_RESULTS[@]}; do
    echo "    - $sa: ${STORAGE_RESULTS[$sa]}"
done
echo
echo "All specified security features have been attempted for resources in $RESOURCE_GROUP."
