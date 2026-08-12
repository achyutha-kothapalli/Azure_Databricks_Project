resource "azurerm_data_factory_linked_service_web" "github_raw" {
  name                = "ls_github_raw"
  data_factory_id     = azurerm_data_factory.platform.id
  authentication_type = "Anonymous"
  url                 = var.adf_source_base_url
  description         = "Commit-pinned public source repository."
}

resource "azurerm_data_factory_linked_service_data_lake_storage_gen2" "data_lake" {
  name                 = "ls_adls_gen2"
  data_factory_id      = azurerm_data_factory.platform.id
  url                  = azurerm_storage_account.data_lake.primary_dfs_endpoint
  use_managed_identity = true
  description          = "ADLS Gen2 accessed through the Data Factory managed identity."
}

resource "azurerm_data_factory_dataset_json" "dataset_manifest" {
  name                = "ds_dataset_manifest"
  data_factory_id     = azurerm_data_factory.platform.id
  linked_service_name = azurerm_data_factory_linked_service_web.github_raw.name
  description         = "Canonical metadata that drives ingestion."

  http_server_location {
    relative_url = "/"
    path         = "config"
    filename     = "datasets.json"
  }
}

resource "azurerm_data_factory_dataset_delimited_text" "source_csv" {
  name                = "ds_source_csv"
  data_factory_id     = azurerm_data_factory.platform.id
  linked_service_name = azurerm_data_factory_linked_service_web.github_raw.name
  description         = "Parameterized CSV source in the commit-pinned repository."

  parameters = {
    source_path = ""
  }

  column_delimiter    = ","
  encoding            = "UTF-8"
  first_row_as_header = true
  quote_character     = "\""
  escape_character    = "\\"

  http_server_location {
    relative_url             = "/"
    path                     = "@substring(dataset().source_path, 0, lastIndexOf(dataset().source_path, '/'))"
    filename                 = "@last(split(dataset().source_path, '/'))"
    dynamic_path_enabled     = true
    dynamic_filename_enabled = true
  }
}

resource "azurerm_data_factory_dataset_delimited_text" "bronze_csv" {
  name                = "ds_bronze_csv"
  data_factory_id     = azurerm_data_factory.platform.id
  linked_service_name = azurerm_data_factory_linked_service_data_lake_storage_gen2.data_lake.name
  description         = "Parameterized bronze-layer CSV sink."

  parameters = {
    sink_folder = ""
    sink_file   = ""
  }

  column_delimiter    = ","
  encoding            = "UTF-8"
  first_row_as_header = true
  quote_character     = "\""
  escape_character    = "\\"

  azure_blob_fs_location {
    file_system              = local.lake_filesystems.bronze
    path                     = "@dataset().sink_folder"
    filename                 = "@dataset().sink_file"
    dynamic_path_enabled     = true
    dynamic_filename_enabled = true
  }
}

resource "azurerm_data_factory_pipeline" "ingest_to_bronze" {
  name            = "pl_ingest_github_to_bronze"
  data_factory_id = azurerm_data_factory.platform.id
  description     = "Loads the canonical dataset manifest and copies every CSV to bronze."
  concurrency     = 1

  activities_json = jsonencode([
    {
      name = "LookupDatasetManifest"
      type = "Lookup"
      policy = {
        timeout                = "0.00:10:00"
        retry                  = 2
        retryIntervalInSeconds = 30
        secureOutput           = false
        secureInput            = false
      }
      typeProperties = {
        source = {
          type = "JsonSource"
          storeSettings = {
            type          = "HttpReadSettings"
            requestMethod = "GET"
          }
          formatSettings = {
            type = "JsonReadSettings"
          }
        }
        dataset = {
          referenceName = azurerm_data_factory_dataset_json.dataset_manifest.name
          type          = "DatasetReference"
        }
        firstRowOnly = false
      }
    },
    {
      name = "ForEachDataset"
      type = "ForEach"
      dependsOn = [
        {
          activity             = "LookupDatasetManifest"
          dependencyConditions = ["Succeeded"]
        }
      ]
      typeProperties = {
        items = {
          value = "@activity('LookupDatasetManifest').output.value"
          type  = "Expression"
        }
        isSequential = false
        batchCount   = 5
        activities = [
          {
            name = "CopyDatasetToBronze"
            type = "Copy"
            policy = {
              timeout                = "0.00:20:00"
              retry                  = 2
              retryIntervalInSeconds = 30
              secureOutput           = false
              secureInput            = false
            }
            inputs = [
              {
                referenceName = azurerm_data_factory_dataset_delimited_text.source_csv.name
                type          = "DatasetReference"
                parameters = {
                  source_path = {
                    value = "@item().source_path"
                    type  = "Expression"
                  }
                }
              }
            ]
            outputs = [
              {
                referenceName = azurerm_data_factory_dataset_delimited_text.bronze_csv.name
                type          = "DatasetReference"
                parameters = {
                  sink_folder = {
                    value = "@item().sink_folder"
                    type  = "Expression"
                  }
                  sink_file = {
                    value = "@item().sink_file"
                    type  = "Expression"
                  }
                }
              }
            ]
            typeProperties = {
              source = {
                type = "DelimitedTextSource"
                storeSettings = {
                  type          = "HttpReadSettings"
                  requestMethod = "GET"
                }
                formatSettings = {
                  type = "DelimitedTextReadSettings"
                }
              }
              sink = {
                type = "DelimitedTextSink"
                storeSettings = {
                  type = "AzureBlobFSWriteSettings"
                }
                formatSettings = {
                  type         = "DelimitedTextWriteSettings"
                  quoteAllText = false
                }
              }
              enableStaging = false
            }
          },
          {
            name = "ValidateBronzeFile"
            type = "GetMetadata"
            dependsOn = [
              {
                activity             = "CopyDatasetToBronze"
                dependencyConditions = ["Succeeded"]
              }
            ]
            policy = {
              timeout                = "0.00:05:00"
              retry                  = 2
              retryIntervalInSeconds = 30
              secureOutput           = false
              secureInput            = false
            }
            typeProperties = {
              dataset = {
                referenceName = azurerm_data_factory_dataset_delimited_text.bronze_csv.name
                type          = "DatasetReference"
                parameters = {
                  sink_folder = {
                    value = "@item().sink_folder"
                    type  = "Expression"
                  }
                  sink_file = {
                    value = "@item().sink_file"
                    type  = "Expression"
                  }
                }
              }
              fieldList = ["exists", "size"]
              storeSettings = {
                type      = "AzureBlobFSReadSettings"
                recursive = false
              }
              formatSettings = {
                type = "DelimitedTextReadSettings"
              }
            }
          },
          {
            name = "EnsureBronzeFileExists"
            type = "IfCondition"
            dependsOn = [
              {
                activity             = "ValidateBronzeFile"
                dependencyConditions = ["Succeeded"]
              }
            ]
            typeProperties = {
              expression = {
                value = "@equals(activity('ValidateBronzeFile').output.exists, true)"
                type  = "Expression"
              }
              ifTrueActivities = []
              ifFalseActivities = [
                {
                  name = "FailMissingBronzeFile"
                  type = "Fail"
                  typeProperties = {
                    message   = "@concat('Bronze file was not created: ', item().sink_folder, '/', item().sink_file)"
                    errorCode = "BRONZE_FILE_MISSING"
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ])
}
