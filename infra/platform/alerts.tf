resource "azurerm_monitor_action_group" "operations" {
  count = var.alert_email == null ? 0 : 1

  name                = "aw-ag-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.platform.name
  short_name          = "aw-${var.environment}"

  email_receiver {
    name                    = "platform-operations"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = local.common_tags
}

resource "azurerm_monitor_metric_alert" "data_factory_pipeline_failure" {
  count = var.alert_email == null ? 0 : 1

  name                = "aw-alert-adf-failure-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.platform.name
  scopes              = [azurerm_data_factory.platform.id]
  description         = "Notify operations when an Adventure Works Data Factory pipeline run fails."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineFailedRuns"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.operations[0].id
  }

  tags = local.common_tags
}
