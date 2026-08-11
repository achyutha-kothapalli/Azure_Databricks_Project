resource "azurerm_role_assignment" "data_factory_storage" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.platform.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "synapse_storage" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.platform.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
