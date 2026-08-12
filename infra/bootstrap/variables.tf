variable "location" {
  description = "Azure region for the Terraform state resources."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "Location must not be empty."
  }
}

variable "region_code" {
  description = "Lowercase region abbreviation used in resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "Region code must contain between 2 and 5 lowercase letters."
  }
}

variable "unique_suffix" {
  description = "Stable suffix that makes the state storage account globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,8}$", var.unique_suffix))
    error_message = "Unique suffix must contain between 4 and 8 lowercase letters or digits."
  }
}

variable "owner" {
  description = "Team or individual responsible for the state resources."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) >= 2 && length(var.owner) <= 64
    error_message = "Owner must contain between 2 and 64 characters."
  }
}

variable "extra_tags" {
  description = "Additional non-sensitive tags applied to state resources."
  type        = map(string)
  default     = {}
}
