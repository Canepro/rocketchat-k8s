terraform {
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "random_string" "storage_suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  storage_account_name = var.storage_account_name != "" ? var.storage_account_name : "${var.storage_account_name_prefix}${random_string.storage_suffix.result}"
}

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(
    var.tags,
    {
      Purpose = "terraform-state"
    }
  )
}

resource "azurerm_storage_account" "state" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  # Keep shared keys enabled for AzureRM provider compatibility during storage resource management.
  # Actual Terraform backend access should still use Azure AD / OIDC via backend.hcl.
  shared_access_key_enabled       = true
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(
    var.tags,
    {
      Purpose = "terraform-state"
    }
  )
}

resource "azurerm_storage_container" "state" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "current_user_blob_data_contributor" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "additional_blob_data_contributor" {
  for_each             = var.additional_blob_data_contributor_principal_ids
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
