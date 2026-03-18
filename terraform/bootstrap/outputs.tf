output "backend_resource_group_name" {
  description = "Resource group name for the Terraform backend"
  value       = azurerm_resource_group.state.name
}

output "backend_storage_account_name" {
  description = "Storage account name for the Terraform backend"
  value       = azurerm_storage_account.state.name
}

output "backend_container_name" {
  description = "Blob container name for the Terraform backend"
  value       = azurerm_storage_container.state.name
}

output "backend_state_key" {
  description = "Blob key for the main AKS Terraform state file"
  value       = var.state_key
}

output "backend_hcl" {
  description = "backend.hcl content for the main AKS Terraform stack"
  value       = <<-EOT
resource_group_name  = "${azurerm_resource_group.state.name}"
storage_account_name = "${azurerm_storage_account.state.name}"
container_name       = "${azurerm_storage_container.state.name}"
key                  = "${var.state_key}"
subscription_id      = "${data.azurerm_client_config.current.subscription_id}"
tenant_id            = "${data.azurerm_client_config.current.tenant_id}"
use_azuread_auth     = true
use_cli              = true
EOT
}
