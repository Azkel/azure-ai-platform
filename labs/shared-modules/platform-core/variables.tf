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
  description = "Address space for the virtual network. For Foundry Agent Service in regions without Class A (10.x) support (e.g. polandcentral), use 172.16.0.0/12 or 192.168.0.0/16 ranges."
  type        = list(string)
  default     = ["172.16.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the agent-delegated subnet. Prefer /24; minimum /27. Must be Microsoft.App/environments-delegated when foundry_agent_network_injection_enabled is true."
  type        = list(string)
  default     = ["172.16.1.0/24"]
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

variable "additional_foundry_user_principal_ids" {
  description = "Extra Entra object IDs to grant Foundry User on the Cognitive Account (interactive users need this for agent data-plane invoke)."
  type        = list(string)
  default     = []
}

variable "foundry_agent_network_injection_enabled" {
  description = "When true, create the Foundry AIServices account with network_injection.scenario=agent into the module subnet. Required for Hosted agents with BYO VNet and MUST be set at account creation time (cannot be added later)."
  type        = bool
  default     = false
}
