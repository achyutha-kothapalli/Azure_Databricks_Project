output "resource_group" {
  description = "Resource group name and resource ID."
  value = {
    name = azurerm_resource_group.platform.name
    id   = azurerm_resource_group.platform.id
  }
}

output "data_lake_storage_account" {
  description = "ADLS Gen2 storage account name and resource ID."
  value = {
    name = azurerm_storage_account.data_lake.name
    id   = azurerm_storage_account.data_lake.id
  }
}

output "lake_filesystem_ids" {
  description = "Resource IDs for the bronze, silver, and Synapse filesystems."
  value = {
    for name, filesystem in azurerm_storage_data_lake_gen2_filesystem.lake :
    name => filesystem.id
  }
}

output "data_factory" {
  description = "Data Factory name, resource ID, and managed identity principal ID."
  value = {
    name         = azurerm_data_factory.platform.name
    id           = azurerm_data_factory.platform.id
    principal_id = azurerm_data_factory.platform.identity[0].principal_id
  }
}

output "databricks_workspace" {
  description = "Azure Databricks workspace name, resource ID, and workspace URL."
  value = {
    name          = azurerm_databricks_workspace.platform.name
    id            = azurerm_databricks_workspace.platform.id
    workspace_url = azurerm_databricks_workspace.platform.workspace_url
  }
}

output "synapse_workspace" {
  description = "Synapse workspace name, resource ID, and managed identity principal ID."
  value = {
    name         = azurerm_synapse_workspace.platform.name
    id           = azurerm_synapse_workspace.platform.id
    principal_id = azurerm_synapse_workspace.platform.identity[0].principal_id
  }
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.platform.id
}
