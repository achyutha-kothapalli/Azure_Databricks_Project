resource "azurerm_databricks_workspace" "platform" {
  count = var.deploy_databricks ? 1 : 0

  name                        = local.resource_names.databricks_workspace
  resource_group_name         = azurerm_resource_group.platform.name
  location                    = azurerm_resource_group.platform.location
  sku                         = var.databricks_sku
  managed_resource_group_name = local.resource_names.databricks_managed_resource_group

  tags = local.common_tags
}
