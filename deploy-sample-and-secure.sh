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
#     [--env <env-name>] [--location <azure-region>] [--subscription <sub-id>] [--use-devcontainer true|false|auto] [--skip-secure] [--secure true|false]
#
# If both --template and --repo-url are omitted, defaults to --template Azure-Samples/azure-search-openai-demo.

TEMPLATE="Azure-Samples/azure-search-openai-demo"
REPO_URL=""
BRANCH="main"
WORKDIR="./upstream/azure-search-openai-demo"
ENV_NAME=""
LOCATION=""
SUBSCRIPTION=""
USE_DEVCONTAINER="auto"
RUN_SECURE=1
TENANT_ID_MODE="auto" # 'auto' or specific tenantId

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template) TEMPLATE="$2"; REPO_URL=""; shift 2;;
    --repo-url) REPO_URL="$2"; TEMPLATE=""; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --workdir) WORKDIR="$2"; shift 2;;
    --env) ENV_NAME="$2"; shift 2;;
    --location|-l) LOCATION="$2"; shift 2;;
  --subscription) SUBSCRIPTION="$2"; shift 2;;
  --tenant-id) TENANT_ID_MODE="$2"; shift 2;;
  --use-devcontainer) USE_DEVCONTAINER="$2"; shift 2;;
  --skip-secure) RUN_SECURE=0; shift 1;;
  --secure) [[ "$2" == "false" ]] && RUN_SECURE=0 || RUN_SECURE=1; shift 2;;
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
      (cd "$WORKDIR" && azd init -t "$TEMPLATE")
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

# 2) Ensure azd environment exists (if ENV_NAME provided) so we can set vars before 'azd up'
ensure_env_if_needed() {
  local envName="$1"; local loc="$2"
  if [[ -n "$envName" ]]; then
    if ! azd env list --output tsv 2>/dev/null | cut -f1 | grep -Fxq "$envName"; then
      echo "Creating azd environment '$envName' (location: ${loc:-inherit}) ..."
      if [[ -n "$loc" ]]; then
        azd env new -e "$envName" -l "$loc" --no-prompt || true
      else
        azd env new -e "$envName" --no-prompt || true
      fi
    else
      echo "(Info) azd environment '$envName' already exists."
    fi
  fi
}

# 3) Resolve tenant id if set to auto
RESOLVED_TENANT_ID=""
if [[ "$TENANT_ID_MODE" == "auto" ]]; then
  RESOLVED_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || true)
else
  RESOLVED_TENANT_ID="$TENANT_ID_MODE"
fi

AZD_UP_ARGS=()
[[ -n "$ENV_NAME" ]] && AZD_UP_ARGS+=( -e "$ENV_NAME" )
[[ -n "$LOCATION" ]] && AZD_UP_ARGS+=( -l "$LOCATION" )

USE_DEV=0
if [[ "$USE_DEVCONTAINER" == "true" ]]; then USE_DEV=1; fi
if [[ "$USE_DEVCONTAINER" == "auto" && -d .devcontainer && $HAS_DEVCONTAINER -eq 1 ]]; then USE_DEV=1; fi

if [[ $USE_DEV -eq 1 ]]; then
  echo "Building/starting dev container for workspace and running 'azd up' inside..."
  devcontainer up --workspace-folder . >/dev/null
  # Create env if specified, then set env vars prior to up
  if [[ -n "$ENV_NAME" ]]; then
    devcontainer exec --workspace-folder . -- bash -lc "azd env list --output tsv | cut -f1 | grep -Fxq '$ENV_NAME' || azd env new -e '$ENV_NAME' -l '${LOCATION:-}' --no-prompt"
  fi
  if [[ -n "$ENV_NAME" ]]; then ENV_FLAG=( -e "$ENV_NAME" ); else ENV_FLAG=(); fi
  # Pre-deploy env settings
  devcontainer exec --workspace-folder . -- azd env set DEPLOYMENT_TARGET appservice "${ENV_FLAG[@]}" || true
  devcontainer exec --workspace-folder . -- azd env set USE_CHAT_HISTORY_COSMOS true "${ENV_FLAG[@]}" || true
  devcontainer exec --workspace-folder . -- azd env set AZURE_USE_AUTHENTICATION true "${ENV_FLAG[@]}" || true
  if [[ -n "$RESOLVED_TENANT_ID" ]]; then
    devcontainer exec --workspace-folder . -- azd env set AZURE_AUTH_TENANT_ID "$RESOLVED_TENANT_ID" "${ENV_FLAG[@]}" || true
  fi
  # Run up
  devcontainer exec --workspace-folder . -- azd up "${AZD_UP_ARGS[@]}"
  # After up, set subscription if requested
  if [[ -n "$SUBSCRIPTION" ]]; then
    CURRENT_ENV=$(devcontainer exec --workspace-folder . -- azd env list --output tsv 2>/dev/null | head -n1 | cut -f1 || true)
    if [[ -z "$CURRENT_ENV" && -n "$ENV_NAME" ]]; then CURRENT_ENV="$ENV_NAME"; fi
    if [[ -n "$CURRENT_ENV" ]]; then
      devcontainer exec --workspace-folder . -- azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION" -e "$CURRENT_ENV"
    fi
  fi
  # Extract RG from inside the container
  RG=$(devcontainer exec --workspace-folder . -- azd env get-values | sed -n 's/^AZURE_RESOURCE_GROUP=//p' | tr -d '\r')
else
  echo "Running 'azd up' on host (this may be interactive) ..."
  # Create env if specified, then set env vars prior to up
  ensure_env_if_needed "$ENV_NAME" "$LOCATION"
  if [[ -n "$ENV_NAME" ]]; then ENV_FLAG=( -e "$ENV_NAME" ); else ENV_FLAG=(); fi
  azd env set DEPLOYMENT_TARGET appservice "${ENV_FLAG[@]}" || true
  azd env set USE_CHAT_HISTORY_COSMOS true "${ENV_FLAG[@]}" || true
  azd env set AZURE_USE_AUTHENTICATION true "${ENV_FLAG[@]}" || true
  if [[ -n "$RESOLVED_TENANT_ID" ]]; then
    azd env set AZURE_AUTH_TENANT_ID "$RESOLVED_TENANT_ID" "${ENV_FLAG[@]}" || true
  fi
  # Run up
  azd up "${AZD_UP_ARGS[@]}"
  # After up, set subscription (if provided) and re-deploy if needed
  if [[ -n "$SUBSCRIPTION" ]]; then
    CURRENT_ENV=$(azd env list --output tsv --only-show-errors 2>/dev/null | head -n1 | cut -f1 || true)
    if [[ -z "$CURRENT_ENV" && -n "$ENV_NAME" ]]; then CURRENT_ENV="$ENV_NAME"; fi
    if [[ -n "$CURRENT_ENV" ]]; then
      azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION" -e "$CURRENT_ENV"
    fi
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
  echo "Skipping security hardening (--skip-secure). Run: $SCRIPT_DIR/azureAISecurityDeploy.sh $RG"
fi
