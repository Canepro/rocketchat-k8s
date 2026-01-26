# Terraform Backend Configuration
# This file defines the backend structure for remote state storage in Azure Storage.
# 
# Backend values are provided via backend.hcl (gitignored) to avoid committing
# environment-specific storage account details.
#
# For Cloud Shell usage:
# 1. Copy backend.hcl.example to backend.hcl
# 2. Update backend.hcl with your actual storage account details
# 3. Run: terraform init -reconfigure -backend-config=backend.hcl
#
# Since Cloud Shell is ephemeral, you'll need to recreate backend.hcl each session,
# or use the init script: ./scripts/tf-init.sh

terraform {
  backend "azurerm" {
    # Backend configuration is provided via backend.hcl file
    # This keeps storage account details out of version control
    # See backend.hcl.example for the required structure
  }
}
