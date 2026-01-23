# Terraform Outputs: Output Values for AKS Infrastructure
# This file defines all output values from the Terraform configuration.
# Outputs are used for: kubectl configuration, ArgoCD configuration, and manual operations.
# Outputs can be viewed with: terraform output (or terraform output <output_name>)

# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the resource group" # Resource group name (for manual operations)
  value       = azurerm_resource_group.main.name
}

# AKS Cluster Outputs
output "cluster_name" {
  description = "Name of the AKS cluster" # Cluster name (for manual operations)
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"            # Cluster FQDN (for manual access)
  value       = azurerm_kubernetes_cluster.main.fqdn # Example: aks-canepro-abc123.hcp.uksouth.azmk8s.io
}

output "cluster_private_fqdn" {
  description = "Private FQDN of the AKS cluster"            # Cluster private FQDN (for internal access)
  value       = azurerm_kubernetes_cluster.main.private_fqdn # Example: aks-canepro-abc123.privatelink.uksouth.azmk8s.io
}

# Kubernetes Configuration Outputs (Sensitive)
# These outputs contain Kubernetes authentication credentials (kubectl config).
output "cluster_kube_config" {
  description = "Raw Kubernetes config to be used by kubectl and other compatible tools" # Full kubectl config (for kubectl access)
  value       = azurerm_kubernetes_cluster.main.kube_config_raw                          # Raw kubeconfig (can be saved to ~/.kube/config)
  sensitive   = true                                                                     # Mark as sensitive (value hidden in Terraform output)
}

output "cluster_host" {
  description = "Kubernetes cluster server host"                    # API server host (from kubeconfig)
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host # Example: https://aks-canepro-abc123.hcp.uksouth.azmk8s.io:443
  sensitive   = true                                                # Mark as sensitive (value hidden in Terraform output)
}

output "cluster_client_key" {
  description = "Base64 encoded private key used by clients to authenticate to the cluster" # Client private key (from kubeconfig)
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_key                   # Base64 encoded private key
  sensitive   = true                                                                        # Mark as sensitive (value hidden in Terraform output)
}

output "cluster_client_certificate" {
  description = "Base64 encoded public certificate used by clients to authenticate to the cluster" # Client certificate (from kubeconfig)
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate                  # Base64 encoded certificate
  sensitive   = true                                                                               # Mark as sensitive (value hidden in Terraform output)
}

output "cluster_cluster_ca_certificate" {
  description = "Base64 encoded public CA certificate used as the root of trust for the cluster" # Cluster CA certificate (from kubeconfig)
  value       = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate            # Base64 encoded CA certificate
  sensitive   = true                                                                             # Mark as sensitive (value hidden in Terraform output)
}

# Node Resource Group Outputs
output "node_resource_group" {
  description = "Resource group containing the AKS node pool VMs (for auto-shutdown configuration)" # Node resource group name (for manual VM access)
  value       = azurerm_kubernetes_cluster.main.node_resource_group                                 # Example: MC_rg-canepro-aks_aks-canepro_uksouth
}

# Managed Identity Outputs
output "managed_identity_principal_id" {
  description = "Principal ID of the System-Assigned Managed Identity (for Jenkins Azure access)" # System-Assigned Managed Identity principal ID (for RBAC)
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id                          # Principal ID (for role assignments)
}

# Key Vault Outputs (for External Secrets Operator configuration)
# These outputs are used to configure ClusterSecretStore (ops/secrets/clustersecretstore-azure-keyvault.yaml)
output "key_vault_name" {
  description = "Name of the Azure Key Vault"     # Key Vault name (for ClusterSecretStore vaultUrl)
  value       = azurerm_key_vault.rocketchat.name # Example: aks-canepro-kv-e8d280
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"           # Key Vault URI (for ClusterSecretStore vaultUrl)
  value       = azurerm_key_vault.rocketchat.vault_uri # Example: https://aks-canepro-kv-e8d280.vault.azure.net/
}

# External Secrets Operator Identity Outputs
output "eso_identity_client_id" {
  description = "Client ID of the User Assigned Managed Identity for External Secrets Operator" # ESO UAMI client ID (for ClusterSecretStore and ArgoCD app)
  value       = azurerm_user_assigned_identity.eso.client_id                                    # Client ID (for Azure Workload Identity annotations)
}

output "eso_identity_principal_id" {
  description = "Principal ID of the User Assigned Managed Identity for External Secrets Operator" # ESO UAMI principal ID (for RBAC role assignments)
  value       = azurerm_user_assigned_identity.eso.principal_id                                    # Principal ID (for role assignments)
}

# Azure AD Tenant Outputs
output "azure_tenant_id" {
  description = "Azure AD Tenant ID (for ClusterSecretStore configuration)" # Azure AD tenant ID (for ClusterSecretStore tenantId)
  value       = data.azurerm_client_config.current.tenant_id                # Tenant ID (from current client config)
}