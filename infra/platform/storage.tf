resource "azurerm_storage_account" "data_lake" {
  name                            = local.resource_names.storage_account
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication_type
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.storage_soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.storage_soft_delete_retention_days
    }
  }

  tags = local.common_tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "lake" {
  for_each = local.lake_filesystems

  name               = each.value
  storage_account_id = azurerm_storage_account.data_lake.id
}
