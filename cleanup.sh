
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

# Optionally, clean up all resources if azd was used
azd down --force --purge

echo "Cleanup complete!"
