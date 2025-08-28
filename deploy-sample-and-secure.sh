#!/usr/bin/env bash
set -euo pipefail

# One-flow helper: fetch the Azure sample app, run `azd up`, then apply security hardening from this repo.
# Works with azd templates or by cloning a repo URL.
#
# Usage:
#   ./deploy-sample-and-secure.sh \
#     [--template Azure-Samples/azure-search-openai-demo] \
#     [--repo-url https://github.com/Azure-Samples/azure-search-openai-demo.git] \
#     [--branch main] \
#     [--workdir ./upstream/azure-search-openai-demo] \
#     [--env <env-name>] [--subscription <sub-id>] [--use-devcontainer true|false|auto]
#
# If both --template and --repo-url are omitted, defaults to --template Azure-Samples/azure-search-openai-demo.

TEMPLATE="Azure-Samples/azure-search-openai-demo"
REPO_URL=""
BRANCH="main"
WORKDIR="./upstream/azure-search-openai-demo"
ENV_NAME=""
SUBSCRIPTION=""
USE_DEVCONTAINER="auto"
# Default: do NOT run security automatically; users will run it explicitly after deploy
RUN_SECURE=0
TENANT_ID_MODE="auto" # 'auto' or specific tenantId

echo "Version 1.4"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template) TEMPLATE="$2"; REPO_URL=""; shift 2;;
    --repo-url) REPO_URL="$2"; TEMPLATE=""; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --workdir) WORKDIR="$2"; shift 2;;
  --env) ENV_NAME="$2"; shift 2;;
  --subscription) SUBSCRIPTION="$2"; shift 2;;
  --tenant-id) TENANT_ID_MODE="$2"; shift 2;;
  --use-devcontainer) USE_DEVCONTAINER="$2"; shift 2;;
    -h|--help) sed -n '1,100p' "$0"; exit 0;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

if ! command -v az &>/dev/null; then echo "Azure CLI 'az' is required."; exit 1; fi
if ! command -v azd &>/dev/null; then echo "Azure Developer CLI 'azd' is required."; exit 1; fi
HAS_DEVCONTAINER=0
if command -v devcontainer &>/dev/null; then HAS_DEVCONTAINER=1; fi

mkdir -p "$WORKDIR"
# Ensure WORKDIR is either empty or already contains the project
if [[ -z "${REPO_URL}${TEMPLATE}" ]]; then TEMPLATE="Azure-Samples/azure-search-openai-demo"; fi

if [[ ! -f "$WORKDIR/azure.yaml" ]]; then
  if [[ -n "$REPO_URL" ]]; then
    if [[ ! -d "$WORKDIR/.git" ]]; then
      echo "Cloning $REPO_URL (branch: $BRANCH) into $WORKDIR ..."
      git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORKDIR"
    else
      echo "Repo exists in $WORKDIR; pulling latest on $BRANCH ..."
      git -C "$WORKDIR" fetch --depth 1 origin "$BRANCH" && git -C "$WORKDIR" checkout "$BRANCH" && git -C "$WORKDIR" pull --ff-only
    fi
  else
    # Initialize from azd template
    if [[ -n "$(ls -A "$WORKDIR" 2>/dev/null || true)" ]]; then
      echo "Workdir $WORKDIR is not empty; skipping 'azd init'." 
    else
      echo "Initializing azd template $TEMPLATE in $WORKDIR ..."
      if [[ -n "$ENV_NAME" ]]; then
        (cd "$WORKDIR" && AZURE_ENV_NAME="$ENV_NAME" azd init -t "$TEMPLATE")
      else
        (cd "$WORKDIR" && azd init -t "$TEMPLATE")
      fi
    fi
  fi
fi

pushd "$WORKDIR" >/dev/null

if [[ -n "$SUBSCRIPTION" ]]; then
  echo "(Info) Subscription will be applied to the azd env after up: $SUBSCRIPTION"
fi

# 1) Update azure.yaml host: containerapp -> host: appservice (pre-deploy)
if [[ -f azure.yaml ]]; then
  if grep -qE "host:\s*containerapp" azure.yaml; then
    echo "Switching compute host to appservice in azure.yaml ..."
    sed -i.bak -E "s/host:\s*containerapp/host: appservice/g" azure.yaml || true
  else
    echo "(Info) No 'host: containerapp' found in azure.yaml; leaving as-is."
  fi
fi

# 2) Sign in (if needed) and set subscription context early to avoid prompts
if ! az account show >/dev/null 2>&1; then
  echo "Signing into Azure (device code flow)..."
  # First try azd login (works well in Codespaces); then ensure az CLI is also logged in
  azd auth login || true
  if ! az account show >/dev/null 2>&1; then
    az login --use-device-code --allow-no-subscriptions || true
  fi
fi
if [[ -n "$SUBSCRIPTION" ]]; then
  echo "Setting active subscription to $SUBSCRIPTION ..."
  az account set --subscription "$SUBSCRIPTION" || true
fi

# 3) Ensure azd environment exists (if ENV_NAME provided) so we can set vars before 'azd up'
ensure_env_if_needed() {
  local envName="$1"
  if [[ -n "$envName" ]]; then
    echo "Ensuring azd environment '$envName' exists and is selected..."
    azd env select "$envName" >/dev/null 2>&1 || azd env new "$envName" --no-prompt || true
  fi
}

# 4) Resolve tenant id if set to auto (after potential login above)
RESOLVED_TENANT_ID=""
if [[ "$TENANT_ID_MODE" == "auto" ]]; then
  RESOLVED_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || true)
  if [[ -z "$RESOLVED_TENANT_ID" ]]; then
    RESOLVED_TENANT_ID=$(az account tenant list --query "[0].tenantId" -o tsv 2>/dev/null || true)
  fi
else
  RESOLVED_TENANT_ID="$TENANT_ID_MODE"
fi

AZD_UP_ARGS=()

USE_DEV=0
if [[ "$USE_DEVCONTAINER" == "true" ]]; then USE_DEV=1; fi
if [[ "$USE_DEVCONTAINER" == "auto" && -d .devcontainer && $HAS_DEVCONTAINER -eq 1 ]]; then USE_DEV=1; fi

if [[ $USE_DEV -eq 1 ]]; then
  echo "Building/starting dev container for workspace and running 'azd up' inside..."
  devcontainer up --workspace-folder . >/dev/null
  # Create/select env if specified (no region pre-seeding; allow interactive prompts)
  if [[ -n "$ENV_NAME" ]]; then
    devcontainer exec --workspace-folder . -- azd env select "$ENV_NAME" >/dev/null 2>&1 || devcontainer exec --workspace-folder . -- azd env new "$ENV_NAME" --no-prompt || true
  fi
  DEV_E_FLAG=() # we operate on active env inside the devcontainer
  # Pre-deploy env settings
  devcontainer exec --workspace-folder . -- azd env set DEPLOYMENT_TARGET appservice "${DEV_E_FLAG[@]}" || true
  devcontainer exec --workspace-folder . -- azd env set USE_CHAT_HISTORY_COSMOS true "${DEV_E_FLAG[@]}" || true
  if [[ -n "$RESOLVED_TENANT_ID" ]]; then
    devcontainer exec --workspace-folder . -- azd env set AZURE_USE_AUTHENTICATION true "${DEV_E_FLAG[@]}" || true
    devcontainer exec --workspace-folder . -- azd env set AZURE_AUTH_TENANT_ID "$RESOLVED_TENANT_ID" "${DEV_E_FLAG[@]}" || true
  fi
  # Ensure subscription is set before 'azd up' to avoid selection prompt
  if [[ -n "$SUBSCRIPTION" ]]; then
    devcontainer exec --workspace-folder . -- az account set --subscription "$SUBSCRIPTION" || true
    devcontainer exec --workspace-folder . -- azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION" || true
  fi
  # Guard: ensure tenant id is present if auth is enabled, else disable auth
  DEV_ENV_ALL=$(devcontainer exec --workspace-folder . -- azd env get-values 2>/dev/null | tr -d '\r' || true)
  DEV_USE_AUTH=$(echo "$DEV_ENV_ALL" | sed -n 's/^AZURE_USE_AUTHENTICATION=//p')
  DEV_TENANT=$(echo "$DEV_ENV_ALL" | sed -n 's/^AZURE_AUTH_TENANT_ID=//p')
  if [[ "${DEV_USE_AUTH,,}" == "true" ]]; then
    if [[ -z "$DEV_TENANT" ]]; then
      DEV_TID="$RESOLVED_TENANT_ID"
      if [[ -z "$DEV_TID" ]]; then DEV_TID=$(devcontainer exec --workspace-folder . -- az account show --query tenantId -o tsv 2>/dev/null | tr -d '\r' || true); fi
      if [[ -z "$DEV_TID" ]]; then DEV_TID=$(devcontainer exec --workspace-folder . -- az account tenant list --query "[0].tenantId" -o tsv 2>/dev/null | tr -d '\r' || true); fi
      if [[ -n "$DEV_TID" ]]; then
        devcontainer exec --workspace-folder . -- azd env set AZURE_AUTH_TENANT_ID "$DEV_TID" || true
      else
        echo "(Warn) AZURE_USE_AUTHENTICATION is enabled but tenant id is unknown; disabling auth for this run."
        devcontainer exec --workspace-folder . -- azd env set AZURE_USE_AUTHENTICATION "" || true
      fi
    fi
  fi
  # Run up
  devcontainer exec --workspace-folder . -- azd up "${AZD_UP_ARGS[@]}"
  # After up, set subscription if requested
  if [[ -n "$SUBSCRIPTION" ]]; then
    devcontainer exec --workspace-folder . -- azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION" || true
  fi
  # Extract RG from inside the container
  RG=$(devcontainer exec --workspace-folder . -- azd env get-values | sed -n 's/^AZURE_RESOURCE_GROUP=//p' | tr -d '\r')
else
  echo "Running 'azd up' on host (this may be interactive) ..."
  # Create env if specified (no region pre-seeding; allow interactive prompts)
  ensure_env_if_needed "$ENV_NAME"
  azd env set DEPLOYMENT_TARGET appservice || true
  azd env set USE_CHAT_HISTORY_COSMOS true || true
  if [[ -n "$RESOLVED_TENANT_ID" ]]; then
    azd env set AZURE_USE_AUTHENTICATION true || true
    azd env set AZURE_AUTH_TENANT_ID "$RESOLVED_TENANT_ID" || true
  fi
  # Ensure subscription is set before 'azd up' to avoid selection prompt
  if [[ -n "$SUBSCRIPTION" ]]; then
    az account set --subscription "$SUBSCRIPTION" || true
    azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION" || true
  fi
  # Guard: ensure tenant id is present if auth is enabled, else disable auth
  ENV_ALL=$(azd env get-values 2>/dev/null | tr -d '\r' || true)
  USE_AUTH=$(echo "$ENV_ALL" | sed -n 's/^AZURE_USE_AUTHENTICATION=//p')
  TID=$(echo "$ENV_ALL" | sed -n 's/^AZURE_AUTH_TENANT_ID=//p')
  if [[ "${USE_AUTH,,}" == "true" ]]; then
    if [[ -z "$TID" ]]; then
      if [[ -z "$RESOLVED_TENANT_ID" ]]; then RESOLVED_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || true); fi
      if [[ -z "$RESOLVED_TENANT_ID" ]]; then RESOLVED_TENANT_ID=$(az account tenant list --query "[0].tenantId" -o tsv 2>/dev/null || true); fi
      if [[ -n "$RESOLVED_TENANT_ID" ]]; then
        azd env set AZURE_AUTH_TENANT_ID "$RESOLVED_TENANT_ID" || true
      else
        echo "(Warn) AZURE_USE_AUTHENTICATION is enabled but tenant id is unknown; disabling auth for this run."
        azd env set AZURE_USE_AUTHENTICATION "" || true
      fi
    fi
  fi
  # Run up
  azd up "${AZD_UP_ARGS[@]}"
  # After up, set subscription (if provided) and re-deploy if needed
  if [[ -n "$SUBSCRIPTION" ]]; then
    azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION" || true
  fi
  # Extract resource group name from azd env (host)
  RG=$(azd env get-values | sed -n 's/^AZURE_RESOURCE_GROUP=//p' | tr -d '\r')
fi
if [[ -z "$RG" ]]; then
  echo "Failed to determine AZURE_RESOURCE_GROUP from azd env."; exit 1
fi

echo "Resource group detected: $RG"

popd >/dev/null

# Invoke security hardening from this repo unless skipped
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Persist azd project info for cleanup
{
  echo "AZD_WORKDIR=$WORKDIR"
  echo "AZD_ENV=$ENV_NAME"
} > "$SCRIPT_DIR/.azd_state.env"
if [[ $RUN_SECURE -eq 1 ]]; then
  "$SCRIPT_DIR/azureAISecurityDeploy.sh" "$RG"
else
  echo "Security hardening step not executed by default. Run: $SCRIPT_DIR/azureAISecurityDeploy.sh $RG"
fi
