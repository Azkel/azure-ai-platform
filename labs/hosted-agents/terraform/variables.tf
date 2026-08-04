variable "workload_name" {
  description = "The workload name for resource naming"
  type        = string
  default     = "hosted-agents"
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry (Basic keeps lab cost low)"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be one of: Basic, Standard, Premium"
  }
}

variable "acr_admin_enabled" {
  description = "Whether admin access is enabled for the Azure Container Registry"
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "SKU for Azure Key Vault (standard keeps lab cost low)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be one of: standard, premium"
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "foundry_project_name" {
  description = "The name of the Microsoft Foundry project for hosted agent deployment"
  type        = string
  default     = "hosted-agents-project"
}

variable "additional_foundry_user_principal_ids" {
  description = "Extra Entra object IDs granted Foundry User on the Foundry account for agent invoke."
  type        = list(string)
  default     = []
}

variable "additional_key_vault_admin_principal_ids" {
  description = "Extra Entra object IDs granted Key Vault Administrator (in addition to the current deployer)."
  type        = list(string)
  default     = []
}

variable "agent_demo_secret_value" {
  description = "User-provided demo secret value stored in Key Vault and read by the hosted agent at runtime via managed identity."
  type        = string
  default     = "Smykpol Labs — greet callers as a concise platform engineer."
  sensitive   = true
}

variable "agent_demo_secret_name" {
  description = "Key Vault secret name the hosted agent reads at runtime."
  type        = string
  default     = "agent-demo-message"
}

variable "storage_blob_container_name" {
  description = "Blob container used by the hosted agent for note persistence."
  type        = string
  default     = "agent-notes"
}

variable "additional_storage_blob_data_contributor_principal_ids" {
  description = "Extra Entra object IDs granted Storage Blob Data Contributor (e.g. local developers). The hosted agent identity is granted post-deploy by the Docker workflow."
  type        = list(string)
  default     = []
}

variable "additional_key_vault_secrets_user_principal_ids" {
  description = "Extra Entra object IDs granted Key Vault Secrets User (e.g. local developers). The hosted agent identity is granted post-deploy by the Docker workflow."
  type        = list(string)
  default     = []
}
