#!/usr/bin/env bash
set -euo pipefail

# Deploy Azure Front Door Standard/Premium + WAF in front of an App Service using Bicep
# Usage:
#   ./deploy-frontdoor.sh <resource-group> [--app <app-service-name>] [--sku Standard_AzureFrontDoor|Premium_AzureFrontDoor] [--profile fd-<rg>] [--endpoint ep-<rg>] [--waf-mode Prevention|Detection]

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 1 ]]; then
  echo "Usage: $0 <resource-group> [--app <app-service-name>] [--sku Standard_AzureFrontDoor|Premium_AzureFrontDoor] [--profile fd-<rg>] [--endpoint ep-<rg>] [--waf-mode Prevention|Detection]"
  exit 1
fi

RG="$1"; shift

SKU="Standard_AzureFrontDoor"
PROFILE_NAME="fd-${RG}"
ENDPOINT_NAME="ep-${RG}"
WAF_MODE="Prevention"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --app) APP_NAME="$2"; shift 2;;
    --sku) SKU="$2"; shift 2;;
    --profile|--profile-name) PROFILE_NAME="$2"; shift 2;;
    --endpoint|--endpoint-name) ENDPOINT_NAME="$2"; shift 2;;
    --waf-mode) WAF_MODE="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

if [[ "$SKU" != "Standard_AzureFrontDoor" && "$SKU" != "Premium_AzureFrontDoor" ]]; then
  echo "--sku must be Standard_AzureFrontDoor or Premium_AzureFrontDoor"; exit 1
fi
if [[ "$WAF_MODE" != "Prevention" && "$WAF_MODE" != "Detection" ]]; then
  echo "--waf-mode must be Prevention or Detection"; exit 1
fi

if [[ ! -f "./infra/frontdoor.bicep" ]]; then
  echo "Error: ./infra/frontdoor.bicep not found. Run from repo root."; exit 1
fi

echo "Discovering App Service in RG '$RG'..."
if [[ -z "${APP_NAME:-}" ]]; then
  # List sites that are not function apps
  APP_NAMES=$(az webapp list -g "$RG" --query "[?contains(kind, 'function')==\`false\`].name" -o tsv | tr -d '\r' || true)
  COUNT=$(echo "$APP_NAMES" | sed '/^$/d' | wc -l | tr -d ' ')
  if [[ "$COUNT" -eq 0 ]]; then
    echo "No App Service found in resource group '$RG'. Pass --app <name>."; exit 1
  elif [[ "$COUNT" -gt 1 ]]; then
    echo "Multiple App Services found in '$RG':"; echo "$APP_NAMES" | sed '/^$/d' | nl -w2 -s') '
    echo "Please re-run with --app <name> to choose one."; exit 1
  else
    APP_NAME="$APP_NAMES"
    echo "Using App Service: $APP_NAME"
  fi
fi

APP_ID=$(az webapp show -g "$RG" -n "$APP_NAME" --only-show-errors --query id -o tsv || true)
APP_HOST=$(az webapp show -g "$RG" -n "$APP_NAME" --only-show-errors --query defaultHostName -o tsv || true)
if [[ -z "$APP_ID" || -z "$APP_HOST" ]]; then
  echo "App Service '$APP_NAME' not found in RG '$RG'"; exit 1
fi

# Enforce HTTPS at the origin (recommended)
echo "Setting httpsOnly=true on App Service..."
az webapp update -g "$RG" -n "$APP_NAME" --set httpsOnly=true 1>/dev/null

DEPLOY_NAME="afd-waf-$(date +%Y%m%d%H%M%S)"

echo "What-if: AFD ($SKU) + WAF -> $APP_NAME"
az deployment group what-if \
  -g "$RG" -n "$DEPLOY_NAME" \
  --template-file ./infra/frontdoor.bicep \
  --parameters profileName="$PROFILE_NAME" endpointName="$ENDPOINT_NAME" appServiceId="$APP_ID" appServiceDefaultHostname="$APP_HOST" wafPolicyName="afd-waf-$RG" sku="$SKU" wafMode="$WAF_MODE" \
  --only-show-errors || true

echo "Deploying..."
ENDPOINT_HOST=$(az deployment group create \
  -g "$RG" -n "$DEPLOY_NAME" \
  --template-file ./infra/frontdoor.bicep \
  --parameters profileName="$PROFILE_NAME" endpointName="$ENDPOINT_NAME" appServiceId="$APP_ID" appServiceDefaultHostname="$APP_HOST" wafPolicyName="afd-waf-$RG" sku="$SKU" wafMode="$WAF_MODE" \
  --only-show-errors --query properties.outputs.endpointHostname.value -o tsv)

echo "Front Door deployed. Test: https://$ENDPOINT_HOST"
echo "Tip: Add a custom domain to Front Door and update app CORS if needed."
