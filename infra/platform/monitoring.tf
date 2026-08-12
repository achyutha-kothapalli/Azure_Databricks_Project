resource "azurerm_log_analytics_workspace" "platform" {
  name                = local.resource_names.log_analytics_workspace
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = local.common_tags
}

resource "azurerm_monitor_diagnostic_setting" "data_factory" {
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_data_factory.platform.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "databricks" {
  count = var.deploy_databricks ? 1 : 0

  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_databricks_workspace.platform[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "synapse" {
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_synapse_workspace.platform.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_storage_account.data_lake.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id

  enabled_metric {
    category = "AllMetrics"
  }
}
