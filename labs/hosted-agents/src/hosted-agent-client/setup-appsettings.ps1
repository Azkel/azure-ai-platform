<#
.SYNOPSIS
    Sets up appsettings.json with Azure AI Foundry endpoint using Azure CLI.

.DESCRIPTION
    This script fetches the Foundry project endpoint from Azure CLI and updates 
    the appsettings.json file with the necessary configuration.

.PARAMETER ProjectName
    The name of the Microsoft Foundry project (default: hosted-agents-project)

.PARAMETER AgentName
    The name of the agent (default: hello-world-dotnet-responses)

.EXAMPLE
    .\setup-appsettings.ps1
    Uses default project and agent names

.EXAMPLE
    .\setup-appsettings.ps1 -ProjectName my-project -AgentName my-agent
    Uses custom project and agent names

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in (az login)
    - Foundry resource must be deployed
    - jq must be installed for JSON parsing (or use the pure PowerShell version)
#>

param (
    [string]$ProjectName = "hosted-agents-project",
    [string]$AgentName = "hello-world-dotnet-responses",
    [string]$FoundryName = "cog-hosted-agents-dev-plc"
)

Write-Host "Setting up appsettings.json for Azure AI Foundry..."
Write-Host "Foundry name: $FoundryName"
Write-Host "Project name: $ProjectName"
Write-Host "Agent name: $AgentName"
Write-Host ""

# Check if Azure CLI is logged in
try {
    $azAccount = az account show 2>$null
    if (-not $azAccount) {
        Write-Error "Azure CLI is not logged in. Please run 'az login' first."
        exit 1
    }
} catch {
    Write-Error "Azure CLI is not installed or not logged in. Please run 'az login' first."
    exit 1
}

# Get the Foundry resource (Cognitive Services account)
Write-Host "Searching for Microsoft Foundry resource..."

try {
    # First, try to find the specific dev Foundry resource by name
    $foundryAccount = az cognitiveservices account show --name $FoundryName --query "{name:name, endpoint:properties.endpoint}" 2>$null
    
    if (-not $foundryAccount -or $foundryAccount -eq "null") {
        # Try to find by name pattern
        $foundryAccount = az cognitiveservices account list --query "[?contains(name,'$FoundryName')].{name:name, endpoint:properties.endpoint} | [0]" 2>$null
    }
    
    if (-not $foundryAccount -or $foundryAccount -eq "null") {
        # Try to find a Foundry-enabled Cognitive Services account
        $foundryAccount = az cognitiveservices account list --query "[?kind=='Microsoft.CognitiveServices/accounts' && contains(properties.customSubDomainName,'foundry')].{name:name, endpoint:properties.endpoint} | [0]" 2>$null
    }
    
    if (-not $foundryAccount -or $foundryAccount -eq "null") {
        # Try alternative query - look for any Cognitive Services account
        $foundryAccount = az cognitiveservices account list --query "[0].{name:name, endpoint:properties.endpoint}" 2>$null
    }
    
    if (-not $foundryAccount -or $foundryAccount -eq "null") {
        Write-Error "No Microsoft Foundry resource found in the current subscription. Please ensure: 1) You are in the correct Azure subscription (run 'az account set --subscription <sub-id>'), 2) The Foundry resource has been deployed"
        exit 1
    }
    
    # Parse the JSON response
    if ($foundryAccount -match '"endpoint":\s*"([^"]+)"') {
        $foundryEndpoint = $matches[1]
    } elseif ($foundryAccount -match '"endpoint":\s*([^\s,]+)') {
        $foundryEndpoint = $matches[1].Trim('"')
    } else {
        # Try using jq if available
        $foundryEndpoint = az cognitiveservices account list --query "[0].properties.endpoint" -o tsv 2>$null
        if (-not $foundryEndpoint) {
            Write-Error "Could not extract endpoint from Foundry resource."
            Write-Host "Resource info: $foundryAccount"
            exit 1
        }
    }
    
    # Ensure the endpoint doesn't have a trailing slash
    $foundryEndpoint = $foundryEndpoint.TrimEnd('/')
    
    # Construct the project endpoint
    $projectEndpoint = "$foundryEndpoint/projects/$ProjectName"
    
    Write-Host "Foundry account endpoint: $foundryEndpoint"
    Write-Host "Project endpoint: $projectEndpoint"
    Write-Host ""
    
    # Create or update appsettings.json
    $appsettingsContent = @{
        FoundrySettings = @{
            Endpoint = $projectEndpoint
            AgentName = $AgentName
        }
    } | ConvertTo-Json -Depth 4
    
    $appsettingsContent | Out-File -FilePath ".\appsettings.json" -Encoding UTF8
    
    Write-Host "✓ appsettings.json has been updated successfully!`n"
    Write-Host "Contents of appsettings.json:"
    Get-Content -Path ".\appsettings.json"
    Write-Host "`nYou can now run the client with: dotnet run"
    
} catch {
    Write-Error "An error occurred: $_"
    exit 1
}
