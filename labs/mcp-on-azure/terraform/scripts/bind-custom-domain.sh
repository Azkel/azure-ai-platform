#!/usr/bin/env bash
# Bind Azure-managed TLS cert after Terraform creates the custom domain + DNS.
# azurerm_container_app_custom_domain often leaves bindingType=Disabled until this step.
set -euo pipefail

APP_NAME="${APP_NAME:-ca-mcp-dev-weu}"
RG="${RG:-rg-mcp-on-azure-dev-weu}"
ENV_NAME="${ENV_NAME:-cae-mcp-on-azure-dev-weu}"
HOSTNAME="${HOSTNAME:-mcp.azure.smyk.it}"

echo "Waiting for managed certificate for ${HOSTNAME}..."
for _ in $(seq 1 36); do
  STATE=$(az containerapp env certificate list -g "$RG" -n "$ENV_NAME" --managed-certificates-only \
    --query "[?properties.subjectName=='${HOSTNAME}'].properties.provisioningState | [0]" -o tsv 2>/dev/null || true)
  echo "  provisioningState=${STATE:-none}"
  [[ "$STATE" == "Succeeded" ]] && break
  [[ "$STATE" == "Failed" ]] && { echo "Certificate failed"; exit 1; }
  sleep 10
done

az containerapp hostname bind \
  -n "$APP_NAME" \
  -g "$RG" \
  --hostname "$HOSTNAME" \
  --environment "$ENV_NAME" \
  --validation-method CNAME

echo "Bound. Smoke: curl -fsS https://${HOSTNAME}/health"
