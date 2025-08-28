#!/usr/bin/env bash
set -euo pipefail

# Remove Azure Front Door profile (and nested resources)
# Usage:
#   ./remove-frontdoor.sh <resource-group> [--profile fd-<rg>]

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 1 ]]; then
  echo "Usage: $0 <resource-group> [--profile fd-<rg>]"
  exit 1
fi

RG="$1"; shift
PROFILE_NAME="fd-${RG}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|--profile-name) PROFILE_NAME="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

ID=$(az resource show -g "$RG" -n "$PROFILE_NAME" --resource-type Microsoft.Cdn/profiles --query id -o tsv 2>/dev/null || true)
if [[ -z "$ID" ]]; then
  echo "Front Door profile '$PROFILE_NAME' not found in RG '$RG'"; exit 0
fi

echo "Deleting AFD profile '$PROFILE_NAME' in RG '$RG'..."
az resource delete --ids "$ID" --verbose --only-show-errors

echo "Done."
