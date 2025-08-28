# Azure AI Security Demo Lab

[![Open in GitHub Codespaces](https://img.shields.io/static/v1?style=for-the-badge&label=GitHub+Codespaces&message=Open&color=brightgreen&logo=github)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=matthansen0%2Fazure-ai-security-demo-lab&machine=standardLinux32gb&devcontainer_path=.devcontainer%2Fdevcontainer.json&location=WestUs2)
[![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https%3A%2F%2Fgithub.com%2Fmatthansen0%2Fazure-ai-security-demo-lab)

## Overview

> [!WARNING]  
> This repo is still under development, and has not yet reached v1.0 release.

This repo provides automation to deploy AI Workloads on Azure using Azure OpenAI and supporting resources, and to enable key Azure Security configurations. This automation uses the fantastic work built by the [Azure Search OpenAI Demo](https://github.com/Azure-Samples/azure-search-openai-demo) samples repo and builds additional security components. We swap the frontend to use Azure App Service, and also enable the flags for conversation history, which requires Cosmos DB and Entra ID.

After we deploy the *azure-search-openai-demo* environment, we run the automation to leverage some bolt-on, and some build-in security:

- Deploy an Azure Front Door + WAF in front of Azure App Service
- Enable Azure Defender for App Service
- Enable Azure Defender for Storage
- Enable Azure Defender for AI
- Enable Azure Defender for Cosmos DB

## Instructions

### Quick Start (3 steps)

1) Open in Codespaces or VS Code Dev Container by clicking a badge above.

2) Deploy the sample from a terminal in the dev container.

```bash
./deploy-sample-and-secure.sh --env azure-ai-search-demo --location westus2
 ```

3) Apply security hardening (includes Front Door + WAF by default)

```bash
./azureAISecurityDeploy.sh
 ```


*If azd environment resource group auto-detection fails, the script will prompt for the resource group name. You can still run it explicitly with `./azureAISecurityDeploy.sh <RESOURCE_GROUP_NAME>`.*


> [!NOTE]  
> If prompted for subscription-wide enablement (App Services or Cosmos DBs), you may accept to enable them now. This creates a local state file `.defender_state.env` so cleanup can revert the change later if desired.


## To-Do List
 
- [ ] Optional: One-click Defender plans for App Services and Cosmos DBs at subscription scope (currently behind a user prompt).
- [ ] Integrate image vulnerability scanning for Azure Container Registry (see: [Defender for ACR](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-container-registries-introduction))
- [ ] Integrate data-aware threat protection and security posture features (see: [Data-aware security](https://learn.microsoft.com/azure/defender-for-cloud/concept-data-aware-security))
- [ ] Add APIM with Defender for APIs (see: [Defender for APIs](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-apis-introduction))
- [ ] Build SQL data source and enable Defender for SQL (see: [Defender for SQL](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-sql-introduction))
- [ ] Deploy Microsoft Purview for Data Classification, and DLP.
- [ ] Integrate Azure AI Content Safety in application code (see: [overview](https://learn.microsoft.com/azure/ai-services/content-safety/overview))
- [ ] Add user guides for walking through verifying each aspect of the solution's security measures.

## Cleanup / Deletion

Run the cleanup script from this repo:

```bash
./cleanup.sh <RESOURCE_GROUP_NAME>
```

What it does:

- Purges the entire azure-search-openai-sample app
- Removes the additional Azure Front Door deployment
- Offers to revert any subscription-wide Defender plan changes that were enabled by the secure step (App Services, Cosmos DBs) back to Free.
