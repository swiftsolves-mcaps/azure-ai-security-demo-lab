# Azure AI Security Demo Lab

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=matthansen0%2Fazure-ai-security-demo-lab)
[![Open in Dev Containers](https://img.shields.io/badge/Open%20in-Dev%20Container-blue?logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https%3A%2F%2Fgithub.com%2Fmatthansen0%2Fazure-ai-security-demo-lab)

## Overview

> [!WARNING]  
> This repo is still under development, and has not yet reached v1.0 release.

This repo provides automation to deploy AI Workloads on Azure using Azure OpenAI and supporting resources, and to enable key Microsoft Defender protections post-deployment.
It also includes an optional Azure Front Door Standard/Premium with WAF to protect the web app with a global edge and layer-7 firewall.

## Instructions

### Quick Start (3 steps)

1) Open in Codespaces or VS Code Dev Container
	- Click a badge above, or “Reopen in Container” locally.

2) Deploy the sample (choose one)
	 - VS Code task: “Deploy sample + secure (devcontainer)” (runs deployment in the sample’s dev container), or
	 - Terminal (host or container):

		 ```bash
		 ./deploy-sample-and-secure.sh --use-devcontainer auto --env demo --location eastus --skip-secure
		 ```

3) Apply security hardening
	 - VS Code task: “Secure existing RG”, or
	 - Terminal:

		 ```bash
		 ./azureAISecurityDeploy.sh <RESOURCE_GROUP_NAME>
		 ```

1. Deploy the sample application/repo as designed, using your preferred method (e.g., Azure Portal, CLI, or automation). Follow the instructions in the original sample repo: <https://github.com/Azure-Samples/azure-search-openai-javascript>

If you deployed the sample using `azd`, you can find the resource group name with:

```bash
azd env get-values | grep AZURE_RESOURCE_GROUP | cut -d '=' -f2
```

Run this command in the root directory of your azd project. The output will be the resource group name to use with the security script.

1. After deployment, note the name of the resource group where you deployed the resources.

1. Clone or upload this repo and run the security enablement script in Azure Cloud Shell or your local environment:

```sh
./azureAISecurityDeploy.sh <RESOURCE_GROUP_NAME>
```

Replace `<RESOURCE_GROUP_NAME>` with the name of your deployed resource group.

1. The script will:
	- Check if Defender plans are already enabled at the subscription level for AI and Storage, and skip resource-level enablement if they are.
	- Enable Defender for AI (workspace-setting) for OpenAI resources in your resource group (if the AI plan isn’t already enabled subscription-wide).
	- Enable Defender for Storage per storage account using the ARM API (if the Storage plan isn’t already enabled subscription-wide).
	- Optionally prompt to enable Defender plans for App Services and Cosmos DBs at the subscription level (these plans cannot be scoped to a resource group). If you opt in, the action is recorded and can be reverted by the cleanup script.
	- Optionally prompt to deploy Azure Front Door + WAF in front of your App Service using the provided Bicep (auto-detects the App Service if only one exists in the resource group).

1. If prompted for subscription-wide enablement (App Services or Cosmos DBs), you may accept to enable them now. This creates a local state file `.defender_state.env` so cleanup can revert the change later if desired.

### (Optional) One-flow: fetch sample, deploy with azd, then secure

If you prefer to run everything from this repo without opening the sample in Codespaces, use:

```bash
./deploy-sample-and-secure.sh \
	--template Azure-Samples/azure-search-openai-demo \
	--workdir ./upstream/azure-search-openai-demo \
	--env <env-name> --location <azure-region> [--subscription <sub-id>]
```

This will initialize or clone the sample, run `azd up`, detect the resource group, and then optionally run `./azureAISecurityDeploy.sh <RG>` (omit by passing `--skip-secure`).

### (Optional) Azure Front Door + WAF in the main script

During `./azureAISecurityDeploy.sh`, you’ll be prompted to deploy Azure Front Door (Standard/Premium) with a WAF policy in front of your App Service. The script:

- Auto-detects your App Service if only one exists in the resource group (otherwise it will skip with guidance)
- Sets the App Service to `httpsOnly=true`
- Deploys AFD via `infra/frontdoor.bicep` with sane defaults (profile `fd-<rg>`, endpoint `ep-<rg>`, SKU Standard, WAF in Prevention mode)
- Prints the default AFD endpoint (e.g., `https://ep-<rg>.azurefd.net`)

If you prefer to deploy AFD separately, you can use the standalone bash helpers:

```bash
# Deploy separately (auto-detects app if single app exists when not provided)
./deploy-frontdoor.sh <rg> [--app <webapp-name>] --sku Standard_AzureFrontDoor --profile fd-<rg> --endpoint ep-<rg>
```

## Current Behavior

- Defender for AI (OpenAI): Enabled by wiring the default workspace-setting to your Log Analytics workspace, unless the AI plan is already enabled at the subscription level.
- Defender for Storage: Enabled per storage account via ARM API, unless the Storage plan is already enabled at the subscription level.
- Defender for App Services and Cosmos DBs: Azure supports these plans only at the subscription level. The script will warn and optionally enable them subscription-wide with user confirmation and record this in `.defender_state.env` for optional revert during cleanup.
- Front Door + WAF (optional): Separate IaC template and scripts so you can add/remove the edge/WAF without touching Defender settings.
	Now also integrated as an optional step in the main deploy script.

## To-Do List

- [x] Microsoft Defender for AI
- [x] Microsoft Defender for Storage
- [ ] Optional: One-click Defender plans for App Services and Cosmos DBs at subscription scope (currently behind a user prompt).
- [ ] Integrate image vulnerability scanning for Azure Container Registry (see: [Defender for ACR](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-container-registries-introduction))
- [ ] Integrate data-aware threat protection and security posture features (see: [Data-aware security](https://learn.microsoft.com/azure/defender-for-cloud/concept-data-aware-security))
- [ ] Add APIM with Defender for APIs (see: [Defender for APIs](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-apis-introduction))
- [ ] Build SQL data source and enable Defender for SQL (see: [Defender for SQL](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-sql-introduction))
- [ ] Deploy Microsoft Purview for Data Classification, and DLP.
- [ ] Integrate Azure AI Content Safety in application code (see: [overview](https://learn.microsoft.com/azure/ai-services/content-safety/overview))

> **Note:** If you want to enable additional security features, you can extend the script to include more Azure security controls as needed.

## Files

- `azureAISecurityDeploy.sh`: Post-deployment security setup for Defender for AI and Storage, with optional Front Door + WAF deploy
- `cleanup.sh`: Reverts Defender changes and optionally removes the Front Door profile
- `infra/frontdoor.bicep`: Bicep template for Azure Front Door + WAF in front of an App Service
- `deploy-frontdoor.sh`: Bash script to deploy Front Door + WAF (optional, standalone)
- `remove-frontdoor.sh`: Bash script to remove the Front Door profile (optional, standalone)

## Cleanup / Deletion

Once you're done with the environment, go back to the Cloud Shell, `cd` to the `azure-search-openai-javascript` folder and run:

```sh
azd down --force --purge
```

If you enabled subscription-wide Defender plans via this script and want to revert them, run `./cleanup.sh <RESOURCE_GROUP_NAME>` from this repo; you will be prompted to reset App Services and Cosmos DBs Defender plans back to Free, based on the `.defender_state.env` state file.

If you created Front Door via the main script, `./cleanup.sh <RESOURCE_GROUP_NAME>` will prompt to remove the Front Door profile (defaults to `fd-<rg>`). To remove AFD separately:

```bash
./remove-frontdoor.sh <rg> --profile fd-<rg>
```
