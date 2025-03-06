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

# Fetch Web App URI
echo "Deployment complete. Fetching Web App URI..."
azd env get-values | grep WEBAPP_URI

# Cleanup instruction
echo "To clean up the environment later, run: azd down --force --purge"

# Enable Defender for Cloud
#az security pricing create --name "Microsoft.DefenderForCloud" --tier "Standard"

# Enable Private Link for OpenAI, AI Search, and Storage
#az network private-endpoint create --name "openai-pe" --resource-group "myResourceGroup" --subnet "mySubnet" --private-connection-resource-id "/subscriptions/{subId}/resourceGroups/{rgName}/providers/Microsoft.CognitiveServices/accounts/{openaiAccountName}" --group-id "account"

# Restrict Blob Storage Public Access
#az storage account update --name mystorageaccount --resource-group myResourceGroup --public-network-access Disabled

# Configure Key Vault with Access Policies
#az keyvault create --name "myKeyVault" --resource-group "myResourceGroup"
#az keyvault set-policy --name "myKeyVault" --object-id $(az ad signed-in-user show --query objectId -o tsv) --secret-permissions get list

# Enable Defender for Storage
#az security setting update --name "DefenderForStorage" --value "Enabled"

# Configure AI Content Moderation
#az openai deployment update --resource-group myResourceGroup --account-name myOpenAI --deployment-name myModel --moderation-level "High"

