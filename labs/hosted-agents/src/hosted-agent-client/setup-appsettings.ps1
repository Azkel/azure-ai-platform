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
    [string]$FoundryName = "cog-hosted-agents-dev-weu"
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
    $query = "{name:name, endpoint:properties.endpoint, customSubDomainName:properties.customSubDomainName}"

    # First, try to find the specific dev Foundry resource by name
    $foundryAccount = az cognitiveservices account show --name $FoundryName --query $query 2>$null
    
    if (-not $foundryAccount -or $foundryAccount -eq "null") {
        # Try to find by name pattern
        $foundryAccount = az cognitiveservices account list --query "[?contains(name,'$FoundryName')].$query | [0]" 2>$null
    }
    
    if (-not $foundryAccount -or $foundryAccount -eq "null") {
        # Try to find an AIServices account
        $foundryAccount = az cognitiveservices account list --query "[?kind=='AIServices'].$query | [0]" 2>$null
    }
    
    if (-not $foundryAccount -or $foundryAccount -eq "null") {
        # Try alternative query - look for any Cognitive Services account
        $foundryAccount = az cognitiveservices account list --query "[0].$query" 2>$null
    }
    
    if (-not $foundryAccount -or $foundryAccount -eq "null") {
        Write-Error "No Microsoft Foundry resource found in the current subscription. Please ensure: 1) You are in the correct Azure subscription (run 'az account set --subscription <sub-id>'), 2) The Foundry resource has been deployed"
        exit 1
    }
    
    $subdomain = $null
    $accountEndpoint = $null
    if ($foundryAccount -match '"customSubDomainName":\s*"([^"]+)"') {
        $subdomain = $matches[1]
    }
    if ($foundryAccount -match '"endpoint":\s*"([^"]+)"') {
        $accountEndpoint = $matches[1]
    }

    if (-not $subdomain) {
        $subdomain = az cognitiveservices account show --name $FoundryName --query properties.customSubDomainName -o tsv 2>$null
    }
    if (-not $subdomain) {
        Write-Error "Could not extract customSubDomainName from Foundry resource."
        Write-Host "Resource info: $foundryAccount"
        exit 1
    }
    
    # Hosted agent APIs use services.ai.azure.com/api/projects/{name}
    $projectEndpoint = "https://$subdomain.services.ai.azure.com/api/projects/$ProjectName"
    
    Write-Host "Foundry account endpoint: $accountEndpoint"
    Write-Host "Custom subdomain: $subdomain"
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
