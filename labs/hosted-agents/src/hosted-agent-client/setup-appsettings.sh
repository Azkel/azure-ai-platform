#!/bin/bash

# Script to populate appsettings.json with Azure AI Foundry endpoint using Azure CLI
# and ensure the signed-in identity has Foundry User (required for agent invoke),
# plus Key Vault / Storage data-plane roles for demo ground-truth lookups.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPSETTINGS_FILE="${SCRIPT_DIR}/appsettings.json"

# Default values (dev environment)
PROJECT_NAME="hosted-agents-project"
AGENT_NAME="storage-kv-agent"
FOUNDRY_NAME="cog-hosted-agents-dev-weu"
KEY_VAULT_NAME="kv-hosted-agents-dev-weu"
# Empty = auto-discover newest sthostedagents* account in the lab RG
STORAGE_ACCOUNT_NAME=""
STORAGE_ACCOUNT_PREFIX="sthostedagents"
RESOURCE_GROUP_NAME="rg-hosted-agents-dev-weu"
FOUNDRY_ROLE="Foundry User"
KEY_VAULT_ROLE="Key Vault Secrets User"
STORAGE_ROLE="Storage Blob Data Contributor"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -p, --project NAME       Foundry project name (default: ${PROJECT_NAME})"
    echo "  -a, --agent NAME         Agent name (default: ${AGENT_NAME})"
    echo "  -k, --key-vault NAME     Key Vault name (default: ${KEY_VAULT_NAME})"
    echo "  -s, --storage NAME       Storage account name (default: auto-discover sthostedagents* in lab RG)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Example:"
    echo "  $0"
    echo "  $0 -p my-project -a my-agent"
    echo ""
    echo "Prerequisites:"
    echo "  - Azure CLI must be installed and logged in (az login)"
    echo "  - Foundry, Key Vault, and Storage resources must be deployed"
    echo "  - Caller must be able to create role assignments (Owner / RBAC Admin)"
    echo "    so this script can grant:"
    echo "      • '${FOUNDRY_ROLE}' (agent invoke)"
    echo "      • '${KEY_VAULT_ROLE}' (read demo secret)"
    echo "      • '${STORAGE_ROLE}' (list/read agent note blobs)"
    echo ""
}

# Ensure a role assignment exists for the signed-in identity on the given scope.
# Args: role_name, scope_id, resource_label
ensure_role_assignment() {
    local role_name="$1"
    local scope_id="$2"
    local resource_label="$3"

    echo "Ensuring '${role_name}' on ${resource_label}..."

    local existing
    existing=$(az role assignment list \
      --assignee-object-id "$OBJECT_ID" \
      --scope "$scope_id" \
      --role "$role_name" \
      --query '[0].id' -o tsv 2>/dev/null || true)

    if [[ -n "$existing" && "$existing" != "null" ]]; then
        echo "✓ '${role_name}' already assigned."
        return 0
    fi

    echo "Assigning '${role_name}' on ${resource_label}..."
    if ! az role assignment create \
      --assignee-object-id "$OBJECT_ID" \
      --assignee-principal-type "$PRINCIPAL_TYPE" \
      --role "$role_name" \
      --scope "$scope_id" \
      --output none; then
        echo "Error: Failed to assign '${role_name}'."
        echo "Your identity needs Owner or Role Based Access Control Administrator"
        echo "on ${resource_label} (or its resource group) to create this assignment."
        exit 1
    fi
    echo "✓ '${role_name}' assigned. Propagation can take up to a few minutes."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -a|--agent)
            AGENT_NAME="$2"
            shift 2
            ;;
        -k|--key-vault)
            KEY_VAULT_NAME="$2"
            shift 2
            ;;
        -s|--storage)
            STORAGE_ACCOUNT_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo "Setting up appsettings.json for Azure AI Foundry..."
echo "Project name: ${PROJECT_NAME}"
echo "Agent name: ${AGENT_NAME}"
echo "Key Vault: ${KEY_VAULT_NAME}"
if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
    echo "Storage account: ${STORAGE_ACCOUNT_NAME}"
else
    echo "Storage account: (auto-discover ${STORAGE_ACCOUNT_PREFIX}* in ${RESOURCE_GROUP_NAME})"
fi
echo ""

# Check if Azure CLI is logged in
if ! az account show > /dev/null 2>&1; then
    echo "Error: Azure CLI is not logged in. Please run 'az login' first."
    exit 1
fi

# Get the Foundry resource (Cognitive Services account with Foundry)
echo "Searching for Microsoft Foundry resource..."

# First, try to find the specific dev Foundry resource by name
FOUNDRY_ACCOUNT=$(az cognitiveservices account show \
  --name "$FOUNDRY_NAME" \
  --query "{name:name, id:id, endpoint:properties.endpoint, customSubDomainName:properties.customSubDomainName, resourceGroup:resourceGroup}" \
  2>/dev/null || true)

if [[ -z "$FOUNDRY_ACCOUNT" || "$FOUNDRY_ACCOUNT" == "null" ]]; then
    # Try to find a Foundry-enabled Cognitive Services account by name pattern
    FOUNDRY_ACCOUNT=$(az cognitiveservices account list \
      --query "[?contains(name,'$FOUNDRY_NAME')].{name:name, id:id, endpoint:properties.endpoint, customSubDomainName:properties.customSubDomainName, resourceGroup:resourceGroup} | [0]" \
      2>/dev/null || true)
fi

if [[ -z "$FOUNDRY_ACCOUNT" || "$FOUNDRY_ACCOUNT" == "null" ]]; then
    # Try to find a Foundry-enabled Cognitive Services account
    FOUNDRY_ACCOUNT=$(az cognitiveservices account list \
      --query "[?kind=='AIServices'].{name:name, id:id, endpoint:properties.endpoint, customSubDomainName:properties.customSubDomainName, resourceGroup:resourceGroup} | [0]" \
      2>/dev/null || true)
fi

if [[ -z "$FOUNDRY_ACCOUNT" || "$FOUNDRY_ACCOUNT" == "null" ]]; then
    # Try alternative query - look for any Cognitive Services account
    FOUNDRY_ACCOUNT=$(az cognitiveservices account list \
      --query "[0].{name:name, id:id, endpoint:properties.endpoint, customSubDomainName:properties.customSubDomainName, resourceGroup:resourceGroup}" \
      2>/dev/null || true)
fi

if [[ -z "$FOUNDRY_ACCOUNT" || "$FOUNDRY_ACCOUNT" == "null" ]]; then
    echo "Error: No Microsoft Foundry resource found in the current subscription."
    echo "Please ensure:"
    echo "  1. You are in the correct Azure subscription (run 'az account set --subscription <sub-id>')"
    echo "  2. The Foundry resource has been deployed"
    exit 1
fi

ACCOUNT_ENDPOINT=$(echo "$FOUNDRY_ACCOUNT" | jq -r '.endpoint // empty' 2>/dev/null || echo "")
SUBDOMAIN=$(echo "$FOUNDRY_ACCOUNT" | jq -r '.customSubDomainName // empty' 2>/dev/null || echo "")
FOUNDRY_ID=$(echo "$FOUNDRY_ACCOUNT" | jq -r '.id // empty' 2>/dev/null || echo "")
FOUNDRY_ACCOUNT_NAME=$(echo "$FOUNDRY_ACCOUNT" | jq -r '.name // empty' 2>/dev/null || echo "")

if [[ -z "$SUBDOMAIN" || "$SUBDOMAIN" == "null" ]]; then
    echo "Error: Could not extract customSubDomainName from Foundry resource."
    echo "Resource info: $FOUNDRY_ACCOUNT"
    exit 1
fi

if [[ -z "$FOUNDRY_ID" || "$FOUNDRY_ID" == "null" ]]; then
    echo "Error: Could not resolve Foundry account resource ID for RBAC."
    echo "Resource info: $FOUNDRY_ACCOUNT"
    exit 1
fi

# Hosted agent APIs use services.ai.azure.com/api/projects/{name}
# (not cognitiveservices.azure.com/projects/...).
PROJECT_ENDPOINT="https://${SUBDOMAIN}.services.ai.azure.com/api/projects/${PROJECT_NAME}"

echo "Foundry account: ${FOUNDRY_ACCOUNT_NAME}"
echo "Foundry account endpoint: ${ACCOUNT_ENDPOINT}"
echo "Custom subdomain: ${SUBDOMAIN}"
echo "Project endpoint: ${PROJECT_ENDPOINT}"
echo ""

# Resolve Key Vault and Storage resource IDs for demo ground-truth RBAC.
echo "Resolving Key Vault and Storage Account..."

KEY_VAULT_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv 2>/dev/null || true)
if [[ -z "$KEY_VAULT_ID" || "$KEY_VAULT_ID" == "null" ]]; then
    echo "Error: Key Vault '${KEY_VAULT_NAME}' not found in the current subscription."
    echo "Pass -k/--key-vault with the correct name, or ensure the lab Terraform has been applied."
    exit 1
fi

STORAGE_ID=""
if [[ -z "$STORAGE_ACCOUNT_NAME" ]]; then
    STORAGE_ACCOUNT_NAME=$(az storage account list \
      --resource-group "$RESOURCE_GROUP_NAME" \
      --query "sort_by([?starts_with(name, '${STORAGE_ACCOUNT_PREFIX}')], &creationTime)[-1].name" \
      -o tsv 2>/dev/null || true)
fi

if [[ -n "$STORAGE_ACCOUNT_NAME" && "$STORAGE_ACCOUNT_NAME" != "null" ]]; then
    STORAGE_ID=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --query id -o tsv 2>/dev/null || true)
fi

if [[ -z "$STORAGE_ID" || "$STORAGE_ID" == "null" ]]; then
    echo "Error: Storage Account not found."
    echo "Pass -s/--storage with the name (e.g. sthostedagentsdevweu1234), or ensure lab Terraform has been applied."
    exit 1
fi

echo "Resolved storage account: ${STORAGE_ACCOUNT_NAME}"
echo "Key Vault ID: ${KEY_VAULT_ID}"
echo "Storage Account ID: ${STORAGE_ID}"
echo ""

# Resolve signed-in identity once; reuse for all role assignments.
# Owner alone is not enough for Foundry — Foundry User is required on the account.
echo "Resolving signed-in identity for RBAC..."

OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
PRINCIPAL_TYPE="User"

if [[ -z "$OBJECT_ID" || "$OBJECT_ID" == "null" ]]; then
    # Federated / SP login: resolve object id from the account client id.
    CLIENT_ID=$(az account show --query user.name -o tsv 2>/dev/null || true)
    if [[ -n "$CLIENT_ID" && "$CLIENT_ID" != "null" ]]; then
        OBJECT_ID=$(az ad sp show --id "$CLIENT_ID" --query id -o tsv 2>/dev/null || true)
        PRINCIPAL_TYPE="ServicePrincipal"
    fi
fi

if [[ -z "$OBJECT_ID" || "$OBJECT_ID" == "null" ]]; then
    echo "Error: Could not resolve signed-in identity object ID for role assignment."
    echo "Assign roles manually, then re-run:"
    echo "  - '${FOUNDRY_ROLE}' on ${FOUNDRY_ACCOUNT_NAME}"
    echo "  - '${KEY_VAULT_ROLE}' on ${KEY_VAULT_NAME}"
    echo "  - '${STORAGE_ROLE}' on ${STORAGE_ACCOUNT_NAME}"
    exit 1
fi

echo "Signed-in object ID: ${OBJECT_ID} (${PRINCIPAL_TYPE})"
echo ""

# Foundry: agent invoke / agents/write
ensure_role_assignment "$FOUNDRY_ROLE" "$FOUNDRY_ID" "$FOUNDRY_ACCOUNT_NAME"
echo ""

# Key Vault: read agent-demo-message for ground truth
ensure_role_assignment "$KEY_VAULT_ROLE" "$KEY_VAULT_ID" "$KEY_VAULT_NAME"
echo ""

# Storage: list/read note blobs written by the agent
ensure_role_assignment "$STORAGE_ROLE" "$STORAGE_ID" "$STORAGE_ACCOUNT_NAME"
echo ""

# Create or update appsettings.json
cat > "$APPSETTINGS_FILE" <<EOF
{
  "FoundrySettings": {
    "Endpoint": "${PROJECT_ENDPOINT}",
    "AgentName": "${AGENT_NAME}"
  }
}
EOF

echo "✓ appsettings.json has been updated successfully!"
echo ""
echo "Contents of ${APPSETTINGS_FILE}:"
cat "$APPSETTINGS_FILE"
echo ""
echo "You can now run the client with: dotnet run"
echo "If you still see a 403, wait briefly for RBAC propagation and retry."
echo ""
echo "Demo ground-truth lookups (after RBAC propagates):"
echo "  az keyvault secret show --vault-name ${KEY_VAULT_NAME} --name agent-demo-message --query value -o tsv"
echo "  az storage blob list --account-name ${STORAGE_ACCOUNT_NAME} --container-name agent-notes --auth-mode login --prefix notes/ -o table"
