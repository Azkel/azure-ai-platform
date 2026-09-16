variable "subscription_id" {
  description = "Azure subscription for this lab. Set via terraform.tfvars (gitignored) or ARM_SUBSCRIPTION_ID."
  type        = string
}

variable "use_oidc" {
  description = "Use OIDC for Azure auth (GitHub Actions). Leave false for local Azure CLI."
  type        = bool
  default     = false
}

variable "workload_name" {
  description = "Workload name used in resource naming"
  type        = string
  default     = "mcp-on-azure"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westeurope"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vnet_address_space" {
  description = "VNet address space"
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "cae_subnet_prefix" {
  description = "Subnet for Container Apps Environment (Microsoft.App/environments delegation)"
  type        = list(string)
  default     = ["10.20.0.0/23"]
}

variable "pe_subnet_prefix" {
  description = "Subnet for private endpoints"
  type        = list(string)
  default     = ["10.20.2.0/24"]
}

variable "storage_blob_container_name" {
  description = "Demo blob container (user.* tools may read when granted Storage Blob Data Reader on this container)"
  type        = string
  default     = "mcp-demo"
}

variable "storage_platform_only_container_name" {
  description = "Container readable only by the MCP managed identity (demo deny path for user.* tools). Subscription Owner does not grant blob data-plane access."
  type        = string
  default     = "mcp-platform-only"
}

variable "acr_sku" {
  description = "ACR SKU"
  type        = string
  default     = "Basic"
}

variable "mcp_image" {
  description = "Container image for the MCP server (ACR path after first push). Empty uses a temporary hello image until you build."
  type        = string
  default     = ""
}

variable "entra_client_id" {
  description = "Entra app (client) ID for Container Apps Easy Auth. Empty = auth not configured yet (Phase 3)."
  type        = string
  default     = ""
}

variable "entra_client_secret" {
  description = "Entra app client secret for Easy Auth (local/dev only). Prefer Key Vault reference in CI."
  type        = string
  default     = ""
  sensitive   = true
}

variable "additional_storage_blob_data_reader_principal_ids" {
  description = "Optional IaC-managed readers on mcp-demo only. Prefer scripts/grant-demo-blob-reader.sh for meetup demos (explicit, not baked into core apply)."
  type        = list(string)
  default     = []
}

variable "container_apps_vnet_injection" {
  description = "Inject Container Apps Environment into the CAE subnet. Set false only as a temporary lab fallback if VNet CAE provisioning fails in-region."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
