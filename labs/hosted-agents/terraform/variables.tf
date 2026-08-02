variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "workload_name" {
  description = "The workload name for resource naming"
  type        = string
  default     = "hosted-agents"
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry. For labs, use 'Basic' for cost optimization. For production, consider 'Standard' or 'Premium'"
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
  description = "SKU for Azure Key Vault. For labs, use 'standard' for cost optimization. For production, consider 'premium'"
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