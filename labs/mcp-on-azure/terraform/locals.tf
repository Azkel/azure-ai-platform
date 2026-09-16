locals {
  location_short_codes = {
    "polandcentral"  = "plc"
    "eastus"         = "eus"
    "westeurope"     = "weu"
    "northeurope"    = "neu"
    "uksouth"        = "uks"
  }

  location_short = lookup(local.location_short_codes, var.location, substr(var.location, 0, 3))
  environment    = var.environment
  workload       = var.workload_name
  # ACR / storage names: alphanumeric only
  safe_workload  = replace(var.workload_name, "-", "")

  common_tags = merge({
    Environment = local.environment
    Workload    = local.workload
    Lab         = "mcp-on-azure"
  }, var.tags)

  # Placeholder until first docker push — CA needs a valid image at create time.
  mcp_image = var.mcp_image != "" ? var.mcp_image : "mcr.microsoft.com/dotnet/samples:aspnetapp"
}
