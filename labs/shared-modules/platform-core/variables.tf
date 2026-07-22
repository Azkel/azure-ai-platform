variable "workload_name" {
  description = "The workload name (e.g., 'shared', 'hosted-agents')"
  type        = string
  default     = "shared"
}

variable "resource_group_name" {
  description = "The name of the resource group. If not provided, will be generated as: rg-{workload}-{environment}-{location-short}"
  type        = string
  default     = null
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "polandcentral"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace. If not provided, will be generated as: law-{workload}-{environment}-{location-short}"
  type        = string
  default     = null
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_in_days" {
  description = "Retention period for Log Analytics data. For cost optimization in labs, we use minimal retention (30 days). For production environments, consider 365 days or more for compliance and long-term analysis."
  type        = number
  default     = 30
}

variable "foundry_sku" {
  description = "SKU for Microsoft Foundry Cognitive Account. For labs, use 'S0' for cost optimization. For production, consider 'F0' or higher for more capacity."
  type        = string
  default     = "S0"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}