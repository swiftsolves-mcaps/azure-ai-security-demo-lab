#!/bin/bash
set -e  # Exit immediately if any command fails

# Convert script to Unix format in case of CRLF issues
sed -i 's/\r$//' "$0"

# Clone the repository
git clone https://github.com/Azure-Samples/azure-search-openai-javascript
cd azure-search-openai-javascript

# Ensure `azd` is initialized
if ! azd env list | grep -q "aisec"; then
    echo "Initializing azd project..."
    azd init -e aisec
fi

# Ensure NVM is installed and sourced correctly
export NVM_DIR="$HOME/.nvm"

if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
else
    echo "NVM not found, installing..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
    source "$HOME/.bashrc"
    source "$NVM_DIR/nvm.sh"
fi

# Verify if NVM is available after sourcing
if ! command -v nvm &> /dev/null; then
    echo "Error: NVM is still not available. Exiting."
    exit 1
fi

# Install & use Node.js 22
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
# Enable Security Components
#####

# Load environment variables safely
echo "Fetching environment values..."
azd env get-values > env_vars.sh
source env_vars.sh

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

echo "Security configurations successfully applied!"

# Fetch Web App URI
echo "Deployment complete. Fetching Web App URI..."
azd env get-values | grep WEBAPP_URI

# Cleanup instruction
echo "To clean up the environment later, please run the cleanup script: cleanup.sh"
