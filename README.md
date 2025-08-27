# Azure AI Security Demo Lab

## Overview

> [!WARNING]  
> This repo is still under development, and has not yet reached v1.0 release.

This repo provides automation to deploy AI Workloads on Azure using Azure OpenAI, and other supporting resources, to demonstrated the end-to-end security story of AI Security on Azure.

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

## To-Do List

- [x] Microsoft Defender for AI
- [x] Microsoft Defender for Storage
- [ ] Integrate [image vulnerability scanning](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-container-registry/image-vulnerability-assessment) for Azure Container Registry
- [ ] Integrate data-aware threat protection and security posture [features](https://learn.microsoft.com/en-us/azure/defender-for-cloud/data-aware-security-dashboard-overview)
- [ ] Add APIM for with [Defender for APIs](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-apis-introduction).
- [ ] Build SQL Data Source and enable [Defender for SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/azure-defender-for-sql?view=azuresql)
- [ ] Deploy Microsoft Purview for Data Classification, and DLP.
- [ ] Integrate Azure AI Content Safety [in application code](https://learn.microsoft.com/en-us/azure/ai-services/content-safety/overview).

> **Note:** If you want to enable additional security features, you can extend the script to include more Azure security controls as needed.

## Deletion

Once you're done with the environment, go back to the Cloud Shell, `cd` to the `azure-search-openai-javascript` folder and run:

```sh
azd down --force --purge
```
