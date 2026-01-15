variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-canepro-aks"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "uksouth"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-canepro"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "VM size for worker nodes"
  type        = string
  default     = "Standard_B2s"
}

variable "kubernetes_version" {
  description = "Kubernetes version (leave empty for latest)"
  type        = string
  default     = ""
}

variable "dns_prefix" {
  description = "DNS prefix for AKS cluster"
  type        = string
  default     = "aks-canepro"
}

variable "enable_auto_shutdown" {
  description = "Enable auto-shutdown for worker nodes (for cost optimization)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

# Key Vault variables
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault (standard or premium)"
  type        = string
  default     = "standard"
}

variable "key_vault_purge_protection" {
  description = "Enable purge protection on Key Vault (prevents immediate deletion)"
  type        = bool
  default     = false
}

variable "key_vault_network_default_action" {
  description = "Default network action for Key Vault (Allow or Deny)"
  type        = string
  default     = "Allow"
  validation {
    condition     = contains(["Allow", "Deny"], var.key_vault_network_default_action)
    error_message = "key_vault_network_default_action must be either 'Allow' or 'Deny'."
  }
}

# Secret values (sensitive - must be provided via terraform.tfvars, never committed)
variable "rocketchat_mongo_uri" {
  description = "MongoDB connection URI for Rocket.Chat (sensitive - set in terraform.tfvars)"
  type        = string
  sensitive   = true
}

variable "rocketchat_mongo_oplog_uri" {
  description = "MongoDB oplog connection URI for Rocket.Chat (sensitive - set in terraform.tfvars)"
  type        = string
  sensitive   = true
}

variable "mongodb_admin_password" {
  description = "MongoDB admin user password (sensitive - set in terraform.tfvars)"
  type        = string
  sensitive   = true
}

variable "mongodb_rocketchat_password" {
  description = "MongoDB rocketchat user password (sensitive - set in terraform.tfvars)"
  type        = string
  sensitive   = true
}

variable "mongodb_metrics_endpoint_password" {
  description = "MongoDB metrics endpoint password (sensitive - set in terraform.tfvars)"
  type        = string
  sensitive   = true
}