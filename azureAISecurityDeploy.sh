#Prereqs

git clone https://github.com/Azure-Samples/azure-search-openai-javascript
cd azure-search-openai-javascript

#If In CloudShell, upgrade NPM & Node for Web App

curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash

source ~/.bashrc 

nvm install 22
nvm use 22

#Initialize https://github.com/Azure-Samples/azure-search-openai-javascript?tab=readme-ov-file#deploying-from-scratch

#This AZD up takes on average 20-25 minutes
azd up -e aisec --no-prompt

#Web App URI
azd env get-values | grep WEBAPP_URI

# Note: to cleanup this environment later ``azd down --force --purge``