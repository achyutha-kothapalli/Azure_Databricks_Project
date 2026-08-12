variable "environment" {
  description = "Deployment environment name."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod."
  }
}

variable "location" {
  description = "Azure region used for platform resources."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "Location must not be empty."
  }
}

variable "region_code" {
  description = "Lowercase region abbreviation used in resource names, for example weu."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "Region code must contain between 2 and 5 lowercase letters."
  }
}

variable "project_name" {
  description = "Lowercase project identifier used in resource names and tags."
  type        = string
  default     = "adventure-works"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "Project name must be 3-20 characters and contain lowercase letters, digits, or hyphens."
  }
}

variable "unique_suffix" {
  description = "Stable lowercase alphanumeric suffix used for globally unique Azure resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,8}$", var.unique_suffix))
    error_message = "Unique suffix must contain between 4 and 8 lowercase letters or digits."
  }
}

variable "owner" {
  description = "Team or individual responsible for the deployed environment."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) >= 2 && length(var.owner) <= 64
    error_message = "Owner must contain between 2 and 64 characters."
  }
}

variable "databricks_sku" {
  description = "Azure Databricks workspace SKU."
  type        = string
  default     = "premium"

  validation {
    condition     = contains(["standard", "premium"], var.databricks_sku)
    error_message = "Databricks SKU must be standard or premium."
  }
}

variable "deploy_databricks" {
  description = "Whether to deploy the Databricks workspace and its managed Azure resources."
  type        = bool
  default     = false
}

variable "storage_replication_type" {
  description = "Replication type for the ADLS Gen2 storage account."
  type        = string
  default     = "LRS"

  validation {
    condition = contains(
      ["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"],
      var.storage_replication_type
    )
    error_message = "Storage replication must be LRS, ZRS, GRS, RAGRS, GZRS, or RAGZRS."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention period in days."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "storage_soft_delete_retention_days" {
  description = "Blob and container soft-delete retention period in days."
  type        = number
  default     = 7

  validation {
    condition = (
      var.storage_soft_delete_retention_days >= 1 &&
      var.storage_soft_delete_retention_days <= 365
    )
    error_message = "Storage soft-delete retention must be between 1 and 365 days."
  }
}

variable "extra_tags" {
  description = "Additional non-sensitive tags merged with the required platform tags."
  type        = map(string)
  default     = {}
}
