locals {
  name_suffix = "${var.environment}-${var.region_code}-${var.unique_suffix}"

  resource_names = {
    resource_group                    = "aw-rg-${local.name_suffix}"
    storage_account                   = "awst${var.environment}${var.region_code}${var.unique_suffix}"
    data_factory                      = "aw-adf-${local.name_suffix}"
    databricks_workspace              = "aw-dbw-${local.name_suffix}"
    databricks_managed_resource_group = "aw-dbw-mrg-${local.name_suffix}"
    synapse_workspace                 = "aw-syn-${local.name_suffix}"
    log_analytics_workspace           = "aw-law-${local.name_suffix}"
  }

  lake_filesystems = {
    bronze  = "bronze"
    silver  = "silver"
    synapse = "synapse"
  }

  common_tags = merge(var.extra_tags, {
    project     = var.project_name
    environment = var.environment
    managed-by  = "terraform"
    owner       = var.owner
    purpose     = "portfolio"
  })
}
