# Terraform remote backend configuration.
# The actual backend values live in the local-only backend.hcl file.
# Bootstrap the state storage first from terraform/bootstrap/, then run:
# terraform init -reconfigure -backend-config=backend.hcl
terraform {
  backend "azurerm" {}
}
