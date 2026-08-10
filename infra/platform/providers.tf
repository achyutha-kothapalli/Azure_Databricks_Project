provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.DataFactory",
    "Microsoft.Databricks",
    "Microsoft.Insights",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
    "Microsoft.Synapse",
  ]
}

