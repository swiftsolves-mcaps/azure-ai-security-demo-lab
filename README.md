# Azure AI Security Demo Lab

## Overview

This repo deploys the Azure Samples Environment from https://github.com/Azure-Samples/azure-search-openai-javascript.

## Deployment

The ``azureAISecurityDeploy.sh`` file is designed to be run in Azure Cloud Shell.

After uploading, wget, or cloning the file you simply run ``./azureAISecurityDeploy`` from a bash Cloud Shell.

## Deletion

Once you're done with the environment, go back to the Cloud Shell, ''cd'' to the ``azure-search-openai-javascript`` folder and run ``azd down --force --purge``.

### Troubleshooting

- File won't execute: Make sure you have permissions set on the file correctly, you can do this by running ``chmod +x azureAISecurityDeploy.sh`` and try executing it again.

- You get the following error: ``bash: ./azureAISecurityDeploy.sh: /bin/bash^M: bad interpreter: No such file or directory``, there may be Windows-style line endings and you can run the following commmand ``sed -i 's/\r$//' azureAISecurityDeploy.sh``.
