#!/bin/bash
set -e  # Exit on error

cd azure-search-openai-javascript

# Load environment variables
echo "Fetching environment values..."
eval $(azd env get-values --format env)

echo "Starting cleanup of security configurations for environment: $AZURE_ENV_NAME"

# Disable Microsoft Defender for AI
echo "Disabling Defender for AI on OpenAI Service: $AZURE_OPENAI_SERVICE"
az security workspace-setting delete \
    --name "$AZURE_OPENAI_SERVICE"

# Disable Defender for Storage
echo "Disabling Defender for Storage on Storage Account: $AZURE_STORAGE_ACCOUNT"
az security setting update \
    --name "DefenderForStorage" \
    --resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
    --value "Disabled"

# Remove Azure AI Content Moderation settings
echo "Disabling Azure AI Content Safety for OpenAI Service: $AZURE_OPENAI_SERVICE"
az openai deployment update \
    --resource-group "$AZURE_OPENAI_RESOURCE_GROUP" \
    --account-name "$AZURE_OPENAI_SERVICE" \
    --deployment-name "$AZURE_OPENAI_CHATGPT_DEPLOYMENT" \
    --moderation-level "Off"

# Disable App Service Authentication
#echo "Disabling App Service Authentication for Static Web App"
#az webapp auth update \
#    --name "$WEBAPP_URI" \
#    --resource-group "$AZURE_RESOURCE_GROUP" \
#    --enabled false

echo "Security configurations successfully removed!"

##Azd Env
azd down --force --purge

echo "Cleanup complete!"
