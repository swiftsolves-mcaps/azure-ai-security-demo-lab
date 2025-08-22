
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

# Disable Defender for AI and Content Moderation on OpenAI resources
OPENAI_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.CognitiveServices/accounts" --query "[?kind=='OpenAI'].name" -o tsv)
for openai in $OPENAI_RESOURCES; do
    echo "Disabling Defender for AI on OpenAI resource: $openai"
    az security workspace-setting delete --name "$openai" || true

    # Disable Content Moderation (Content Safety) on all deployments in the OpenAI account
    deployments=$(az cognitiveservices account deployment list --resource-group "$RESOURCE_GROUP" --account-name "$openai" --query "[].name" -o tsv)
    for dep in $deployments; do
        echo "Disabling Content Moderation for deployment: $dep in $openai"
        az openai deployment update --resource-group "$RESOURCE_GROUP" --account-name "$openai" --deployment-name "$dep" --moderation-level "Off" || true
    done
done

# Disable Defender for Container Apps
CONTAINER_APPS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.App/containerApps" --query "[].name" -o tsv)
for ca in $CONTAINER_APPS; do
    echo "Disabling Defender for Container App: $ca"
    az security setting update --name "DefenderForContainers" --resource-group "$RESOURCE_GROUP" --value "Disabled" || true
done

# Disable Defender for Storage
STORAGE_ACCOUNTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Storage/storageAccounts" --query "[].name" -o tsv)
for sa in $STORAGE_ACCOUNTS; do
    echo "Disabling Defender for Storage Account: $sa"
    az security setting update --name "DefenderForStorage" --resource-group "$RESOURCE_GROUP" --value "Disabled" || true
done

echo "Security configurations successfully removed!"

# Optionally, clean up all resources if azd was used
azd down --force --purge

echo "Cleanup complete!"
