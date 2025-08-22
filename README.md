# Azure AI Security Demo Lab

## Overview

This repo provides a script to enable security features on Azure OpenAI resources after you deploy the sample environment.

## Instructions

1. Deploy the sample application/repo as designed, using your preferred method (e.g., Azure Portal, CLI, or automation). Follow the instructions in the original sample repo: https://github.com/Azure-Samples/azure-search-openai-javascript

If you deployed the sample using `azd`, you can find the resource group name with:

```bash
azd env get-values | grep AZURE_RESOURCE_GROUP | cut -d '=' -f2
```

Run this command in the root directory of your azd project. The output will be the resource group name to use with the security script.

2. After deployment, note the name of the resource group where you deployed the resources.

3. Clone or upload this repo and run the security enablement script in Azure Cloud Shell or your local environment:

```sh
./azureAISecurityDeploy.sh <RESOURCE_GROUP_NAME>
```

Replace `<RESOURCE_GROUP_NAME>` with the name of your deployed resource group.

4. The script will find all Azure OpenAI resources in the specified resource group and enable Microsoft Defender for Cloud on them.


## Security Features Enabled

The following security features are enabled by this deployment:

- [ ] AI Content Safety (**TODO:** Integrate Azure AI Content Safety in application code. See https://learn.microsoft.com/en-us/azure/ai-services/content-safety/overview)
- [x] Microsoft Defender for AI
- [x] Microsoft Defender for Storage

> **Note:** If you want to enable additional security features, you can extend the script to include more Azure security controls as needed.

## Deletion

Once you're done with the environment, go back to the Cloud Shell, `cd` to the `azure-search-openai-javascript` folder and run:

```sh
azd down --force --purge
```
