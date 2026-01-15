output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "cluster_private_fqdn" {
  description = "Private FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.private_fqdn
}

output "cluster_kube_config" {
  description = "Raw Kubernetes config to be used by kubectl and other compatible tools"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "cluster_host" {
  description = "Kubernetes cluster server host"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "cluster_client_key" {
  description = "Base64 encoded private key used by clients to authenticate to the cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_key
  sensitive   = true
}

output "cluster_client_certificate" {
  description = "Base64 encoded public certificate used by clients to authenticate to the cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate
  sensitive   = true
}

output "cluster_cluster_ca_certificate" {
  description = "Base64 encoded public CA certificate used as the root of trust for the cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "node_resource_group" {
  description = "Resource group containing the AKS node pool VMs (for auto-shutdown configuration)"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "managed_identity_principal_id" {
  description = "Principal ID of the System-Assigned Managed Identity (for Jenkins Azure access)"
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# Key Vault outputs (for External Secrets Operator configuration)
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.rocketchat.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.rocketchat.vault_uri
}

output "eso_identity_client_id" {
  description = "Client ID of the User Assigned Managed Identity for External Secrets Operator"
  value       = azurerm_user_assigned_identity.eso.client_id
}

output "eso_identity_principal_id" {
  description = "Principal ID of the User Assigned Managed Identity for External Secrets Operator"
  value       = azurerm_user_assigned_identity.eso.principal_id
}

output "azure_tenant_id" {
  description = "Azure AD Tenant ID (for ClusterSecretStore configuration)"
  value       = data.azurerm_client_config.current.tenant_id
}