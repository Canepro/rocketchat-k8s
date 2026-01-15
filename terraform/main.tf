terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Backend configuration for Azure Storage (Remote State)
  #
  # We intentionally keep this backend block empty and supply real values via:
  #   terraform init -backend-config=backend.hcl
  #
  # This avoids committing environment-specific backend settings and works well in Azure Cloud Shell.
  backend "azurerm" {}

  # Example backend config (DO NOT COMMIT REAL VALUES HERE):
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "tfcaneprostate1"
  #   container_name       = "tfstate"
  #   key                  = "aks.terraform.tfstate"
  # }
}

# Configure the Azure Provider
# Uses Azure CLI authentication (az login)
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
    Project     = "RocketChat"
  }
}
