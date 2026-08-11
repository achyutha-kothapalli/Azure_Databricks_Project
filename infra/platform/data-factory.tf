resource "azurerm_data_factory" "platform" {
  name                = local.resource_names.data_factory
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}
