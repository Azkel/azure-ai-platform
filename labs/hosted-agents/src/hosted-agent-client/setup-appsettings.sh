#!/bin/bash

# Script to populate appsettings.json with Azure AI Foundry endpoint using Azure CLI
# This script fetches the Foundry project endpoint and updates the appsettings.json file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPSETTINGS_FILE="${SCRIPT_DIR}/appsettings.json"

# Default values (dev environment)
PROJECT_NAME="hosted-agents-project"
AGENT_NAME="hello-world-dotnet-responses"
FOUNDRY_NAME="cog-hosted-agents-dev-plc"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -p, --project NAME     Foundry project name (default: ${PROJECT_NAME})"
    echo "  -a, --agent NAME       Agent name (default: ${AGENT_NAME})"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Example:"
    echo "  $0"
    echo "  $0 -p my-project -a my-agent"
    echo ""
    echo "Prerequisites:"
    echo "  - Azure CLI must be installed and logged in (az login)"
    echo "  - Foundry resource must be deployed"
    echo ""
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
echo ""

# Check if Azure CLI is logged in
if ! az account show > /dev/null 2>&1; then
    echo "Error: Azure CLI is not logged in. Please run 'az login' first."
    exit 1
fi

# Get the Foundry resource (Cognitive Services account with Foundry)
echo "Searching for Microsoft Foundry resource..."

# First, try to find the specific dev Foundry resource by name
FOUNDRY_ACCOUNT=$(az cognitiveservices account show --name "$FOUNDRY_NAME" --query "{name:name, endpoint:properties.endpoint}" 2>/dev/null || true)

if [[ -z "$FOUNDRY_ACCOUNT" || "$FOUNDRY_ACCOUNT" == "null" ]]; then
    # Try to find a Foundry-enabled Cognitive Services account by name pattern
    FOUNDRY_ACCOUNT=$(az cognitiveservices account list --query "[?contains(name,'$FOUNDRY_NAME')].{name:name, endpoint:properties.endpoint} | [0]" 2>/dev/null || true)
fi

if [[ -z "$FOUNDRY_ACCOUNT" || "$FOUNDRY_ACCOUNT" == "null" ]]; then
    # Try to find a Foundry-enabled Cognitive Services account
    FOUNDRY_ACCOUNT=$(az cognitiveservices account list --query "[?kind=='Microsoft.CognitiveServices/accounts' && contains(properties.customSubDomainName,'foundry')].{name:name, endpoint:properties.endpoint} | [0]" 2>/dev/null || true)
fi

if [[ -z "$FOUNDRY_ACCOUNT" || "$FOUNDRY_ACCOUNT" == "null" ]]; then
    # Try alternative query - look for any Cognitive Services account
    FOUNDRY_ACCOUNT=$(az cognitiveservices account list --query "[0].{name:name, endpoint:properties.endpoint}" 2>/dev/null || true)
fi

if [[ -z "$FOUNDRY_ACCOUNT" || "$FOUNDRY_ACCOUNT" == "null" ]]; then
    echo "Error: No Microsoft Foundry resource found in the current subscription."
    echo "Please ensure:"
    echo "  1. You are in the correct Azure subscription (run 'az account set --subscription <sub-id>')"
    echo "  2. The Foundry resource has been deployed"
    exit 1
fi

# Extract the account endpoint
FOUNDRY_ENDPOINT=$(echo "$FOUNDRY_ACCOUNT" | jq -r '.endpoint' 2>/dev/null || echo "")

if [[ -z "$FOUNDRY_ENDPOINT" ]]; then
    echo "Error: Could not extract endpoint from Foundry resource."
    echo "Resource info: $FOUNDRY_ACCOUNT"
    exit 1
fi

# Ensure the endpoint doesn't have a trailing slash
FOUNDRY_ENDPOINT=$(echo "$FOUNDRY_ENDPOINT" | sed 's/\/$//')

# Construct the project endpoint
PROJECT_ENDPOINT="${FOUNDRY_ENDPOINT}/projects/${PROJECT_NAME}"

echo "Foundry account endpoint: ${FOUNDRY_ENDPOINT}"
echo "Project endpoint: ${PROJECT_ENDPOINT}"
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
