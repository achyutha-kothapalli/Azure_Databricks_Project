resource "azurerm_resource_group" "platform" {
  name     = local.resource_names.resource_group
  location = var.location
  tags     = local.common_tags
}
