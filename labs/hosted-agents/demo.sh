#!/usr/bin/env bash
# Hosted Agents Lab — post-deploy smoke test
#
# Deploy via GitHub Actions first:
#   1. Terraform Deploy - Hosted Agents (apply)
#   2. Docker Build, Push and Deploy - Hosted Agents
#
# Then run this script to resolve live resources and prove KV + Storage tools.

set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$LAB_DIR/.demo-state"

LOCATION_SHORT="weu"
ENVIRONMENT="dev"
WORKLOAD="hosted-agents"
AGENT_NAME="storage-kv-agent"
FOUNDRY_PROJECT_NAME="hosted-agents-project"
RG_NAME="rg-${WORKLOAD}-${ENVIRONMENT}-${LOCATION_SHORT}"
ACR_NAME="acrhostedagents${ENVIRONMENT}${LOCATION_SHORT}"
FOUNDRY_ACCOUNT_NAME="cog-${WORKLOAD}-${ENVIRONMENT}-${LOCATION_SHORT}"
KEY_VAULT_NAME="kv-${WORKLOAD}-${ENVIRONMENT}-${LOCATION_SHORT}"

FOUNDRY_PROJECT_ENDPOINT=""
STORAGE_ACCOUNT=""
KEY_VAULT_URI=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
  echo -e "${BLUE}================================================================${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}================================================================${NC}"
  echo
}

print_step() { echo -e "${YELLOW}>>> $1${NC}"; }
print_success() { echo -e "${GREEN}[✓] $1${NC}"; }
print_warn() { echo -e "${YELLOW}[!] $1${NC}"; }
print_error() { echo -e "${RED}[✗] $1${NC}"; }

require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    print_error "'$cmd' is required but not installed.${hint:+ $hint}"
    exit 1
  fi
}

save_state() {
  umask 077
  cat >"$STATE_FILE" <<EOF
FOUNDRY_PROJECT_ENDPOINT=${FOUNDRY_PROJECT_ENDPOINT}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
KEY_VAULT_URI=${KEY_VAULT_URI}
RG_NAME=${RG_NAME}
ACR_NAME=${ACR_NAME}
KEY_VAULT_NAME=${KEY_VAULT_NAME}
AGENT_NAME=${AGENT_NAME}
EOF
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

check_prerequisites() {
  print_header "PREREQUISITES"
  require_cmd az "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
  require_cmd jq "Install jq"
  require_cmd curl

  if ! az account show &>/dev/null; then
    print_error "Not logged in to Azure. Run: az login"
    exit 1
  fi
  print_success "Azure CLI: $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo ok)"
  print_success "Logged in as: $(az account show --query user.name -o tsv)"
  print_success "Subscription: $(az account show --query name -o tsv)"
  echo
}

resolve_infra() {
  print_header "RESOLVING LAB INFRASTRUCTURE"

  print_step "Resource group $RG_NAME..."
  if ! az group show --name "$RG_NAME" --output none 2>/dev/null; then
    print_error "Resource group '$RG_NAME' not found."
    print_warn "Deploy first: Actions → Terraform Deploy - Hosted Agents (apply),"
    print_warn "then Docker Build, Push and Deploy - Hosted Agents."
    return 1
  fi
  print_success "Resource group exists"

  print_step "ACR $ACR_NAME..."
  if ! az acr show --name "$ACR_NAME" --output none 2>/dev/null; then
    print_error "ACR '$ACR_NAME' not found. Run Terraform Deploy first."
    return 1
  fi
  print_success "ACR exists"

  print_step "Foundry account $FOUNDRY_ACCOUNT_NAME..."
  if ! az cognitiveservices account show \
    --name "$FOUNDRY_ACCOUNT_NAME" \
    --resource-group "$RG_NAME" \
    --output none 2>/dev/null; then
    print_error "Foundry account not found in '$RG_NAME'."
    return 1
  fi

  local subdomain
  subdomain="$(az cognitiveservices account show \
    --name "$FOUNDRY_ACCOUNT_NAME" \
    --resource-group "$RG_NAME" \
    --query properties.customSubDomainName -o tsv)"
  if [[ -z "$subdomain" || "$subdomain" == "None" ]]; then
    print_error "Foundry account has no customSubDomainName"
    return 1
  fi

  FOUNDRY_PROJECT_ENDPOINT="https://${subdomain}.services.ai.azure.com/api/projects/${FOUNDRY_PROJECT_NAME}"
  print_success "Project endpoint: $FOUNDRY_PROJECT_ENDPOINT"

  print_step "Storage account (sthostedagents*)..."
  STORAGE_ACCOUNT="$(az storage account list \
    --resource-group "$RG_NAME" \
    --query "sort_by([?starts_with(name, 'sthostedagents')], &creationTime)[-1].name" \
    -o tsv)"
  if [[ -z "$STORAGE_ACCOUNT" || "$STORAGE_ACCOUNT" == "None" ]]; then
    print_error "No storage account starting with 'sthostedagents' in $RG_NAME."
    return 1
  fi
  print_success "Storage account: $STORAGE_ACCOUNT"

  if ! az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RG_NAME" --output none 2>/dev/null; then
    print_error "Key Vault '$KEY_VAULT_NAME' not found."
    return 1
  fi
  KEY_VAULT_URI="https://${KEY_VAULT_NAME}.vault.azure.net/"
  print_success "Key Vault URI: $KEY_VAULT_URI"

  save_state
  print_success "State saved to $STATE_FILE"
  echo
}

ensure_state() {
  load_state
  if [[ -z "${FOUNDRY_PROJECT_ENDPOINT:-}" || -z "${STORAGE_ACCOUNT:-}" ]]; then
    resolve_infra
  fi
  if [[ -z "${FOUNDRY_PROJECT_ENDPOINT:-}" || -z "${STORAGE_ACCOUNT:-}" ]]; then
    print_error "Cannot continue without resolved infrastructure."
    exit 1
  fi
}

invoke_agent() {
  print_header "SMOKE TEST — INVOKE AGENT"
  ensure_state

  print_step "Getting access token..."
  local token
  token="$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)"
  local url="${FOUNDRY_PROJECT_ENDPOINT}/agents/${AGENT_NAME}/endpoint/protocols/openai/responses?api-version=v1"

  invoke_once() {
    local label="$1"
    local input="$2"
    print_step "$label"
    curl -sS -X POST "$url" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg input "$input" '{input: $input, store: true, stream: false}')" \
      | jq '{status, output}'
    echo
  }

  invoke_once "Q&A (no Azure tools)..." "What is Microsoft Foundry?"
  invoke_once "Key Vault demo secret..." "What is the operator demo message stored in Key Vault?"
  invoke_once "Persist note to Storage..." "Save a note that says demo smoke test completed"
  invoke_once "List recent notes..." "List the recent note blobs you can see"

  print_success "Invoke tests complete"
  print_warn "Screenshot-friendly UI: cd src/hosted-agent-client && ./setup-appsettings.sh && dotnet run"
  echo
}

validate_blobs() {
  print_header "VALIDATE STORAGE"
  ensure_state

  print_step "Listing blobs under notes/ in $STORAGE_ACCOUNT..."
  if az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name agent-notes \
    --auth-mode login \
    --prefix notes/ \
    -o table; then
    print_success "Blob list query succeeded"
  else
    print_warn "No blobs yet, or your identity lacks Storage Blob Data Reader on this account"
  fi
  echo
}

smoke_test() {
  resolve_infra
  invoke_agent
  validate_blobs
  print_header "SMOKE TEST COMPLETE"
  print_success "Agent responded; Key Vault + Storage tools exercised."
  print_warn "Cleanup: Actions → Terraform Cleanup / Deploy (destroy), or wait for the daily 21:00 UTC job."
}

usage() {
  cat <<EOF
Usage: ./demo.sh [command]

  (no args)   Full smoke test: resolve → invoke → validate
  resolve     Discover live lab resources into .demo-state
  invoke      Call the hosted agent (KV + Storage checks)
  validate    List notes/ blobs in the agent storage account
  help        Show this help

Prerequisites: az login; lab deployed via GitHub Actions (Terraform + Docker workflows).
EOF
}

main() {
  local cmd="${1:-all}"

  if [[ "$cmd" == "help" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
    usage
    exit 0
  fi

  echo
  print_header "HOSTED AGENTS LAB — SMOKE TEST"
  echo "Lab: $LAB_DIR"
  echo "RG:  $RG_NAME"
  echo

  check_prerequisites

  case "$cmd" in
    all|"")
      smoke_test
      ;;
    resolve)
      resolve_infra
      ;;
    invoke)
      invoke_agent
      ;;
    validate)
      validate_blobs
      ;;
    *)
      print_error "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
