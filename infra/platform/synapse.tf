resource "azurerm_synapse_workspace" "platform" {
  name                                 = local.resource_names.synapse_workspace
  resource_group_name                  = azurerm_resource_group.platform.name
  location                             = azurerm_resource_group.platform.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.lake["synapse"].id

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}
