#!/bin/bash
set -e  # Exit immediately if any command fails

# Clone the repository
git clone https://github.com/Azure-Samples/azure-search-openai-javascript
cd azure-search-openai-javascript

# Ensure NVM is sourced (Cloud Shell includes NVM)
export NVM_DIR="$HOME/.nvm"
source ~/.nvm/nvm.sh
source ~/.bashrc

# Install & use Node.js 22 (Cloud Shell may have an older version)
echo "Installing Node.js 22..."
nvm install 22
nvm use 22

# Verify installation
echo "Node.js version: $(node -v)"
echo "NPM version: $(npm -v)"

# Deploy (this takes ~20-25 minutes)
echo "Starting Azure deployment..."
azd up -e aisec --no-prompt

echo "Base deployment complete!"

#####
#Enable Security Components
######

# Load environment variables from azd
echo "Fetching environment values..."
eval $(azd env get-values --format env)

echo "Applying security configurations for environment: $AZURE_ENV_NAME"

# Enable Microsoft Defender for AI (specific to OpenAI resource)
echo "Enabling Defender for AI on OpenAI Service: $AZURE_OPENAI_SERVICE"
az security workspace-setting create \
    --name "$AZURE_OPENAI_SERVICE" \
    --target-workspace "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_OPENAI_RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$AZURE_OPENAI_SERVICE-workspace"

# Enable Defender for Storage (only for the storage account)
echo "Enabling Defender for Storage on Storage Account: $AZURE_STORAGE_ACCOUNT"
az security setting update \
    --name "DefenderForStorage" \
    --resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
    --value "Enabled"

# Enable Azure AI Content Moderation (ensure OpenAI does not output harmful content)
echo "Enabling Azure AI Content Safety for OpenAI Service: $AZURE_OPENAI_SERVICE"
az openai deployment update \
    --resource-group "$AZURE_OPENAI_RESOURCE_GROUP" \
    --account-name "$AZURE_OPENAI_SERVICE" \
    --deployment-name "$AZURE_OPENAI_CHATGPT_DEPLOYMENT" \
    --moderation-level "High"

# Enable App Service Authentication for Static Web App
#echo "Enabling App Service Authentication for Static Web App"
#az webapp auth update \
#    --name "$WEBAPP_URI" \
#    --resource-group "$AZURE_RESOURCE_GROUP" \
#    --enabled true \
#    --action "LogInWithAzureActiveDirectory"

echo "Security configurations successfully applied!"

# Fetch Web App URI
echo "Deployment complete. Fetching Web App URI..."
azd env get-values | grep WEBAPP_URI

# Cleanup instruction
echo "To clean up the environment later, please run the cleanup script: cleanup.sh"
