#!/usr/bin/env bash
# Tear down MCP on Azure without hanging forever on Container Apps Environment.
#
# VNet-injected CAEs often sit in provisioningState=ScheduledForDelete while Terraform
# polls until its delete timeout. This script:
#   1. Deletes Container Apps via Azure CLI (unblocks the environment)
#   2. Requests CAE delete / waits if already ScheduledForDelete
#   3. If CAE is still present after CAE_WAIT_MINUTES, deletes the whole lab RG
#      (Azure finishes managed-cluster cleanup more reliably than TF alone)
#   4. Runs terraform destroy for Entra apps, shared DNS records, and leftovers
#
# Usage (from terraform/ after init + az login):
#   ./scripts/teardown.sh \
#     -var=subscription_id=... -var=use_oidc=true \
#     -var=custom_hostname=... -var=dns_zone_name=... \
#     -var=dns_zone_resource_group_name=...
#
# Extra terraform args are forwarded to `terraform destroy`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

CAE_WAIT_MINUTES="${CAE_WAIT_MINUTES:-12}"
POLL_SECONDS="${POLL_SECONDS:-30}"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need az; need terraform; need jq

TF_VARS=("$@")

echo "== resolve lab names from state (fallbacks if outputs missing) =="
RG="$(terraform output -raw resource_group_name 2>/dev/null || true)"
CAE="$(terraform output -raw container_app_environment_name 2>/dev/null || true)"
CA="$(terraform output -raw container_app_name 2>/dev/null || true)"

# Fallbacks match terraform naming defaults (dev / westeurope).
RG="${RG:-rg-mcp-on-azure-dev-weu}"
CAE="${CAE:-cae-mcp-on-azure-dev-weu}"
CA="${CA:-ca-mcp-dev-weu}"

echo "  resource group: ${RG}"
echo "  container app:  ${CA}"
echo "  CAE:            ${CAE}"

rg_exists() {
  az group show -n "$RG" -o none 2>/dev/null
}

cae_state() {
  az containerapp env show -g "$RG" -n "$CAE" --query properties.provisioningState -o tsv 2>/dev/null || echo "Gone"
}

delete_container_apps() {
  if ! rg_exists; then
    echo "RG ${RG} already gone — skip app delete"
    return 0
  fi
  echo "== delete Container Apps in ${RG} =="
  mapfile -t apps < <(az containerapp list -g "$RG" --query "[].name" -o tsv 2>/dev/null || true)
  if [[ ${#apps[@]} -eq 0 ]]; then
    echo "  (none)"
    return 0
  fi
  for app in "${apps[@]}"; do
    echo "  deleting ${app}..."
    az containerapp delete -g "$RG" -n "$app" --yes --no-wait 2>/dev/null || true
  done
  # Brief wait so CAE delete is less likely to 409.
  sleep 15
}

delete_or_wait_cae() {
  if ! rg_exists; then
    echo "RG ${RG} already gone — skip CAE delete"
    return 0
  fi

  local state
  state="$(cae_state)"
  if [[ "$state" == "Gone" ]]; then
    echo "== CAE already gone =="
    return 0
  fi

  echo "== CAE state: ${state} =="
  if [[ "$state" != "ScheduledForDelete" && "$state" != "Deleting" ]]; then
    echo "  requesting az containerapp env delete..."
    az containerapp env delete -g "$RG" -n "$CAE" --yes --no-wait 2>/dev/null || true
  fi

  local max_iters=$(( CAE_WAIT_MINUTES * 60 / POLL_SECONDS ))
  local i
  for ((i = 1; i <= max_iters; i++)); do
    state="$(cae_state)"
    echo "  [${i}/${max_iters}] CAE provisioningState=${state}"
    if [[ "$state" == "Gone" ]]; then
      echo "  CAE deleted"
      return 0
    fi
    sleep "${POLL_SECONDS}"
  done

  echo "== CAE still present after ${CAE_WAIT_MINUTES}m — deleting resource group ${RG} =="
  az group delete -n "$RG" --yes --no-wait 2>/dev/null || true

  max_iters=$(( 30 * 60 / POLL_SECONDS )) # up to 30m for RG
  for ((i = 1; i <= max_iters; i++)); do
    if ! rg_exists; then
      echo "  RG deleted"
      return 0
    fi
    echo "  [${i}/${max_iters}] waiting for RG delete..."
    sleep "${POLL_SECONDS}"
  done

  echo "WARNING: RG ${RG} still exists after wait — terraform destroy will continue"
}

state_rm() {
  local addr="$1"
  echo "  state rm ${addr}"
  terraform state rm -lock=true "$addr" 2>/dev/null || true
}

# Drop managed Azure resources from state when Azure already finished them so
# terraform destroy does not sit on 45m delete timeouts for ghosts.
prune_gone_azure_from_state() {
  echo "== prune gone Azure resources from Terraform state =="
  local addr state
  state="$(cae_state)"

  # CAE path: apps + env + Easy Auth + custom domain often already deleted by CLI.
  if [[ "$state" == "Gone" ]] || ! rg_exists; then
    while IFS= read -r addr; do
      [[ -z "$addr" ]] && continue
      case "$addr" in
        azurerm_container_app.*|azurerm_container_app_environment.*|azurerm_container_app_custom_domain.*|azapi_resource.mcp_auth*)
          state_rm "$addr"
          ;;
      esac
    done < <(terraform state list 2>/dev/null || true)
  fi

  # Whole RG gone (CAE fallback): drop every lab Azure resource; keep Entra + shared DNS.
  if ! rg_exists; then
    while IFS= read -r addr; do
      [[ -z "$addr" ]] && continue
      case "$addr" in
        data.*) continue ;;
        azuread_*) continue ;;
        random_*) continue ;;
        azurerm_dns_*) continue ;; # shared DNS zone records — destroy via TF
        azurerm_*|azapi_*)
          state_rm "$addr"
          ;;
      esac
    done < <(terraform state list 2>/dev/null || true)
  fi
}

delete_container_apps
delete_or_wait_cae
prune_gone_azure_from_state

echo "== terraform destroy (Entra + DNS + leftovers) =="
terraform destroy -auto-approve -input=false "${TF_VARS[@]}"

echo ""
echo "============================================================"
echo "  MCP on Azure demo DESTROYED"
echo "============================================================"
