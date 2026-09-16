variable "custom_hostname" {
  description = "Optional custom hostname for the MCP app (e.g. mcp.azure.smyk.it). Empty skips custom domain."
  type        = string
  default     = ""
}

variable "dns_zone_name" {
  description = "Public DNS zone name that hosts custom_hostname (e.g. azure.smyk.it)"
  type        = string
  default     = ""
}

variable "dns_zone_resource_group_name" {
  description = "Resource group of the public DNS zone"
  type        = string
  default     = ""
}
