<#
.SYNOPSIS
    Sets up appsettings.json with Azure AI Foundry endpoint using Azure CLI.

.DESCRIPTION
    This script fetches the Foundry project endpoint from Azure CLI and updates
    the appsettings.json file with the necessary configuration. It also ensures
    the signed-in identity has:
    - Foundry User (required for agent invoke / agents/write)
    - Key Vault Secrets User (read the demo secret for ground truth)
    - Storage Blob Data Contributor (list/read agent note blobs)

.PARAMETER ProjectName
    The name of the Microsoft Foundry project (default: hosted-agents-project)

.PARAMETER AgentName
    The name of the agent (default: storage-kv-agent)

.PARAMETER FoundryName
    The Foundry Cognitive Services account name (default: cog-hosted-agents-dev-weu)

.PARAMETER KeyVaultName
    The Key Vault name (default: kv-hosted-agents-dev-weu)

.PARAMETER StorageAccountName
    The Storage Account name. When omitted, auto-discovers the newest sthostedagents* account in the lab resource group.

.PARAMETER ResourceGroupName
    Lab resource group used for storage auto-discovery (default: rg-hosted-agents-dev-weu)

.EXAMPLE
    .\setup-appsettings.ps1
    Uses default project/agent/Key Vault names and auto-discovers the storage account

.EXAMPLE
    .\setup-appsettings.ps1 -ProjectName my-project -AgentName my-agent
    Uses custom project and agent names

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in (az login)
    - Foundry, Key Vault, and Storage resources must be deployed
    - Caller must be able to create role assignments (Owner / RBAC Admin)
      so this script can grant Foundry User, Key Vault Secrets User, and
      Storage Blob Data Contributor
#>

param (
    [string]$ProjectName = "hosted-agents-project",
    [string]$AgentName = "storage-kv-agent",
    [string]$FoundryName = "cog-hosted-agents-dev-weu",
    [string]$KeyVaultName = "kv-hosted-agents-dev-weu",
    [string]$StorageAccountName = "",
    [string]$ResourceGroupName = "rg-hosted-agents-dev-weu"
)

$FoundryRole = "Foundry User"
$KeyVaultRole = "Key Vault Secrets User"
$StorageRole = "Storage Blob Data Contributor"
$StorageAccountPrefix = "sthostedagents"

function Ensure-RoleAssignment {
    param (
        [string]$RoleName,
        [string]$ScopeId,
        [string]$ResourceLabel,
        [string]$ObjectId,
        [string]$PrincipalType
    )

    Write-Host "Ensuring '$RoleName' on $ResourceLabel..."

    $existingAssignment = az role assignment list `
        --assignee-object-id $ObjectId `
        --scope $ScopeId `
        --role $RoleName `
        --query '[0].id' -o tsv 2>$null

    if ($existingAssignment -and $existingAssignment -ne "null") {
        Write-Host "✓ '$RoleName' already assigned."
        return
    }

    Write-Host "Assigning '$RoleName' on $ResourceLabel..."
    az role assignment create `
        --assignee-object-id $ObjectId `
        --assignee-principal-type $PrincipalType `
        --role $RoleName `
        --scope $ScopeId `
        --output none

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to assign '$RoleName'. Your identity needs Owner or Role Based Access Control Administrator on $ResourceLabel (or its resource group)."
        exit 1
    }

    Write-Host "✓ '$RoleName' assigned. Propagation can take up to a few minutes."
}

Write-Host "Setting up appsettings.json for Azure AI Foundry..."
Write-Host "Foundry name: $FoundryName"
Write-Host "Project name: $ProjectName"
Write-Host "Agent name: $AgentName"
Write-Host "Key Vault: $KeyVaultName"
if ($StorageAccountName) {
    Write-Host "Storage account: $StorageAccountName"
}
else {
    Write-Host "Storage account: (auto-discover $StorageAccountPrefix* in $ResourceGroupName)"
}
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
    $query = "{name:name, id:id, endpoint:properties.endpoint, customSubDomainName:properties.customSubDomainName, resourceGroup:resourceGroup}"

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

    $account = $foundryAccount | ConvertFrom-Json
    $subdomain = $account.customSubDomainName
    $accountEndpoint = $account.endpoint
    $foundryId = $account.id
    $foundryAccountName = $account.name

    if (-not $subdomain) {
        $subdomain = az cognitiveservices account show --name $FoundryName --query properties.customSubDomainName -o tsv 2>$null
    }
    if (-not $subdomain) {
        Write-Error "Could not extract customSubDomainName from Foundry resource."
        Write-Host "Resource info: $foundryAccount"
        exit 1
    }

    if (-not $foundryId) {
        Write-Error "Could not resolve Foundry account resource ID for RBAC."
        Write-Host "Resource info: $foundryAccount"
        exit 1
    }

    # Hosted agent APIs use services.ai.azure.com/api/projects/{name}
    $projectEndpoint = "https://$subdomain.services.ai.azure.com/api/projects/$ProjectName"

    Write-Host "Foundry account: $foundryAccountName"
    Write-Host "Foundry account endpoint: $accountEndpoint"
    Write-Host "Custom subdomain: $subdomain"
    Write-Host "Project endpoint: $projectEndpoint"
    Write-Host ""

    # Resolve Key Vault and Storage resource IDs for demo ground-truth RBAC.
    Write-Host "Resolving Key Vault and Storage Account..."

    $keyVaultId = az keyvault show --name $KeyVaultName --query id -o tsv 2>$null
    if (-not $keyVaultId -or $keyVaultId -eq "null") {
        Write-Error "Key Vault '$KeyVaultName' not found in the current subscription. Pass -KeyVaultName with the correct name, or ensure the lab Terraform has been applied."
        exit 1
    }

    $storageId = $null
    if (-not $StorageAccountName) {
        $StorageAccountName = az storage account list `
            --resource-group $ResourceGroupName `
            --query "sort_by([?starts_with(name, '$StorageAccountPrefix')], &creationTime)[-1].name" `
            -o tsv 2>$null
    }

    if ($StorageAccountName -and $StorageAccountName -ne "null") {
        $storageId = az storage account show --name $StorageAccountName --query id -o tsv 2>$null
    }

    if (-not $storageId -or $storageId -eq "null") {
        Write-Error "Storage Account not found. Pass -StorageAccountName (e.g. sthostedagentsdevweu1234), or ensure the lab Terraform has been applied."
        exit 1
    }

    Write-Host "Resolved storage account: $StorageAccountName"
    Write-Host "Key Vault ID: $keyVaultId"
    Write-Host "Storage Account ID: $storageId"
    Write-Host ""

    # Resolve signed-in identity once; reuse for all role assignments.
    # Owner alone is not enough for Foundry — Foundry User is required on the account.
    Write-Host "Resolving signed-in identity for RBAC..."

    $objectId = az ad signed-in-user show --query id -o tsv 2>$null
    $principalType = "User"

    if (-not $objectId -or $objectId -eq "null") {
        $clientId = az account show --query user.name -o tsv 2>$null
        if ($clientId) {
            $objectId = az ad sp show --id $clientId --query id -o tsv 2>$null
            $principalType = "ServicePrincipal"
        }
    }

    if (-not $objectId -or $objectId -eq "null") {
        Write-Error "Could not resolve signed-in identity object ID for role assignment. Assign roles manually, then re-run: '$FoundryRole' on $foundryAccountName, '$KeyVaultRole' on $KeyVaultName, '$StorageRole' on $StorageAccountName."
        exit 1
    }

    Write-Host "Signed-in object ID: $objectId ($principalType)"
    Write-Host ""

    # Foundry: agent invoke / agents/write
    Ensure-RoleAssignment -RoleName $FoundryRole -ScopeId $foundryId -ResourceLabel $foundryAccountName -ObjectId $objectId -PrincipalType $principalType
    Write-Host ""

    # Key Vault: read agent-demo-message for ground truth
    Ensure-RoleAssignment -RoleName $KeyVaultRole -ScopeId $keyVaultId -ResourceLabel $KeyVaultName -ObjectId $objectId -PrincipalType $principalType
    Write-Host ""

    # Storage: list/read note blobs written by the agent
    Ensure-RoleAssignment -RoleName $StorageRole -ScopeId $storageId -ResourceLabel $StorageAccountName -ObjectId $objectId -PrincipalType $principalType
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
    Write-Host "If you still see a 403, wait briefly for RBAC propagation and retry."
    Write-Host ""
    Write-Host "Demo ground-truth lookups (after RBAC propagates):"
    Write-Host "  az keyvault secret show --vault-name $KeyVaultName --name agent-demo-message --query value -o tsv"
    Write-Host "  az storage blob list --account-name $StorageAccountName --container-name agent-notes --auth-mode login --prefix notes/ -o table"

} catch {
    Write-Error "An error occurred: $_"
    exit 1
}
