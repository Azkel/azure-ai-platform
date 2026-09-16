variable "enable_entra_auth" {
  description = "Create Entra app registration and enable Container Apps Easy Auth (Phase 3)."
  type        = bool
  default     = true
}

variable "entra_allowed_group_object_ids" {
  description = "Optional Entra group object IDs allowed to call the MCP app. Empty = any user in the tenant (still requires a valid token)."
  type        = list(string)
  default     = []
}
