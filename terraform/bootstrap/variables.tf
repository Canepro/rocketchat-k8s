variable "resource_group_name" {
  description = "Resource group name for the Terraform state backend"
  type        = string
  default     = "rg-canepro-tfstate"
}

variable "location" {
  description = "Azure region for the Terraform state backend"
  type        = string
  default     = "uksouth"
}

variable "storage_account_name" {
  description = "Optional explicit storage account name for Terraform state. Leave empty to auto-generate."
  type        = string
  default     = ""
}

variable "storage_account_name_prefix" {
  description = "Prefix used when auto-generating the storage account name"
  type        = string
  default     = "caneprotf"
}

variable "container_name" {
  description = "Blob container name for Terraform state"
  type        = string
  default     = "tfstate"
}

variable "state_key" {
  description = "Blob key for the main AKS Terraform state file"
  type        = string
  default     = "aks.terraform.tfstate"
}

variable "additional_blob_data_contributor_principal_ids" {
  description = "Additional Azure principal IDs that should be able to read/write/lock Terraform state"
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to Terraform state resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "Terraform"
    Project     = "RocketChat"
  }
}
