# Terraform Configuration: Azure Kubernetes Service (AKS) Infrastructure
# This Terraform configuration provisions Azure infrastructure for Rocket.Chat on AKS.
# It includes: Resource Group, Virtual Network, AKS Cluster, Key Vault, and Azure Automation.
# See VERSIONS.md for Terraform and Azure Provider version tracking.
# See terraform/README.md for setup instructions and usage examples.

terraform {
  # Terraform version requirement: >= 1.8
  # See VERSIONS.md for latest Terraform version and upgrade status
  required_version = ">= 1.8"

  required_providers {
    # Azure Resource Manager provider: Manages Azure resources
    azurerm = {
      source  = "hashicorp/azurerm" # Official Azure provider
      version = "~> 4.0"            # Azure provider version constraint (4.x.x)
      # See VERSIONS.md for latest Azure provider version and upgrade status
    }
  }

  # Backend configuration moved to backend.tf
  # See backend.tf and backend.hcl.example for configuration details
}

# Configure the Azure Provider
# The Azure provider uses Azure CLI authentication (az login) for authentication.
# This means you must be logged in to Azure CLI before running Terraform.
# Uses Azure CLI authentication (az login)
provider "azurerm" {
  features {
    resource_group {
      # Allow resource group deletion even if it contains resources
      # This prevents Terraform from blocking deletion of resource groups with resources
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Resource Group: Container for all Azure resources
# This resource group contains all resources for the AKS Rocket.Chat deployment.
# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name # Resource group name (from variables.tf, default: "rg-canepro-aks")
  location = var.location            # Azure region (from variables.tf, default: "uksouth")

  tags = {
    Environment = "production" # Environment tag (for resource organization)
    ManagedBy   = "Terraform"  # Managed by tag (indicates infrastructure as code)
    Project     = "RocketChat" # Project tag (for cost allocation)
  }
}
