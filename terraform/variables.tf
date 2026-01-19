# Terraform Variables: Input Variables for AKS Infrastructure
# This file defines all input variables for the Terraform configuration.
# Variables can be overridden via terraform.tfvars (gitignored) or command line flags.
# See terraform/README.md for variable usage and terraform.tfvars.example for examples.

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the Azure Resource Group"  # Resource group name for all Azure resources
  type        = string
  default     = "rg-canepro-aks"  # Default resource group name (can be overridden in terraform.tfvars)
}

variable "location" {
  description = "Azure region for resources"  # Azure region where resources will be created
  type        = string
  default     = "uksouth"  # Default Azure region (UK South - can be overridden in terraform.tfvars)
}

# AKS Cluster Configuration
variable "cluster_name" {
  description = "Name of the AKS cluster"  # AKS cluster name (must be unique within resource group)
  type        = string
  default     = "aks-canepro"  # Default cluster name (can be overridden in terraform.tfvars)
}

variable "node_count" {
  description = "Number of worker nodes"  # Number of nodes in the default node pool
  type        = number
  default     = 2  # Default node count (can be overridden in terraform.tfvars)
}

variable "vm_size" {
  description = "VM size for worker nodes (Standard_D4as_v5 recommended for RocketChat + Jenkins + Observability)"  # VM size for worker nodes
  type        = string
  # See VERSIONS.md for VM size tracking. Current: Standard_D4as_v5 (upgraded from Standard_B2s on 2026-01-16)
  default     = "Standard_D4as_v5"  # 4 vCPU, 16GB RAM - sufficient for RocketChat + Jenkins + Loki + traces + metrics
}

variable "kubernetes_version" {
  description = "Kubernetes version (leave empty for latest)"  # Kubernetes version for AKS cluster
  type        = string
  default     = ""  # Empty = use latest stable version (can be overridden in terraform.tfvars to pin version)
}

variable "dns_prefix" {
  description = "DNS prefix for AKS cluster"  # DNS prefix for cluster FQDN (e.g., "aks-canepro" → "aks-canepro-abc123.hcp.uksouth.azmk8s.io")
  type        = string
  default     = "aks-canepro"  # Default DNS prefix (can be overridden in terraform.tfvars)
}

# Azure Automation Configuration (for scheduled AKS start/stop)
variable "enable_auto_shutdown" {
  description = "Enable scheduled AKS stop/start (stops cluster evenings/weekends for cost savings)"  # Enable/disable automated start/stop
  type        = bool
  default     = true  # Default: enabled (can be overridden in terraform.tfvars)
}

variable "shutdown_timezone" {
  description = "Timezone for auto-shutdown schedules (e.g., 'GMT Standard Time' for UK)"  # Timezone for schedules (IANA or Windows timezone)
  type        = string
  default     = "GMT Standard Time"  # Default: GMT Standard Time (UK) (can be overridden in terraform.tfvars)
}

variable "shutdown_time" {
  description = "Time to stop the cluster on weekdays (24h format, e.g., '20:00')"  # Shutdown time (24-hour format)
  type        = string
  default     = "20:00"  # Default: 8:00 PM (can be overridden in terraform.tfvars)
}

variable "startup_time" {
  description = "Time to start the cluster on weekdays (24h format, e.g., '07:00')"  # Startup time (24-hour format)
  type        = string
  default     = "07:00"  # Default: 7:00 AM (can be overridden in terraform.tfvars)
}

# Resource Tags Configuration
variable "tags" {
  description = "Tags to apply to resources"  # Tags for resource organization and cost allocation
  type        = map(string)
  default = {
    Environment = "production"  # Environment tag (production, staging, dev, etc.)
    ManagedBy   = "Terraform"  # Managed by tag (indicates infrastructure as code)
  }
}

# Key Vault Configuration Variables
# Key Vault variables
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault (standard or premium)"  # Key Vault SKU (standard = basic, premium = HSM)
  type        = string
  default     = "standard"  # Default: standard SKU (can be overridden in terraform.tfvars)
}

variable "key_vault_purge_protection" {
  description = "Enable purge protection on Key Vault (prevents immediate deletion)"  # Purge protection (prevents accidental deletion)
  type        = bool
  default     = false  # Default: disabled (can be overridden in terraform.tfvars - enable for production)
}

variable "key_vault_network_default_action" {
  description = "Default network action for Key Vault (Allow or Deny)"  # Network access default action
  type        = string
  default     = "Allow"  # Default: Allow all IPs (can be overridden in terraform.tfvars - use Deny for production)
  validation {
    # Validation: Ensure only valid values are allowed
    condition     = contains(["Allow", "Deny"], var.key_vault_network_default_action)
    error_message = "key_vault_network_default_action must be either 'Allow' or 'Deny'."
  }
}

# Secret Values (Sensitive - Must be provided via terraform.tfvars, NEVER committed)
# ⚠️ IMPORTANT: These variables contain sensitive values and must be set in terraform.tfvars (gitignored).
# Secret values (sensitive - must be provided via terraform.tfvars, never committed)
# See terraform/README.md for terraform.tfvars setup instructions.
# See terraform/terraform.tfvars.example for variable format examples.

variable "rocketchat_mongo_uri" {
  description = "MongoDB connection URI for Rocket.Chat (sensitive - set in terraform.tfvars)"  # MongoDB primary connection string
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
  # Example: "mongodb://rocketchat:password@mongodb-0.mongodb-svc.rocketchat.svc.cluster.local:27017/rocketchat?authSource=rocketchat&replicaSet=mongodb"
}

variable "rocketchat_mongo_oplog_uri" {
  description = "MongoDB oplog connection URI for Rocket.Chat (sensitive - set in terraform.tfvars)"  # MongoDB oplog connection string (for real-time features)
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
  # Example: "mongodb://admin:password@mongodb-0.mongodb-svc.rocketchat.svc.cluster.local:27017/local?authSource=admin&replicaSet=mongodb"
}

variable "mongodb_admin_password" {
  description = "MongoDB admin user password (sensitive - set in terraform.tfvars)"  # MongoDB admin user password (for MongoDB Community Operator)
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
}

variable "mongodb_rocketchat_password" {
  description = "MongoDB rocketchat user password (sensitive - set in terraform.tfvars)"  # MongoDB rocketchat user password (for MongoDB Community Operator)
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
}

variable "mongodb_metrics_endpoint_password" {
  description = "MongoDB metrics endpoint password (sensitive - set in terraform.tfvars)"  # MongoDB metrics endpoint password (for Prometheus scraping)
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
}

variable "observability_username" {
  description = "Observability hub username for basic auth (Grafana/Mimir/Tempo/Loki) (sensitive - set in terraform.tfvars)"  # Username for basic auth to observability hub
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
  # Example: Grafana Cloud instance ID or custom username
}

variable "observability_password" {
  description = "Observability hub password for basic auth (Grafana/Mimir/Tempo/Loki) (sensitive - set in terraform.tfvars)"  # Password for basic auth to observability hub
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
  # Example: Grafana Cloud API key or custom password
}

# Jenkins Credentials: Admin username and password for Jenkins login
variable "jenkins_admin_username" {
  description = "Jenkins admin username (sensitive - set in terraform.tfvars)"  # Admin username for Jenkins login
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
  default     = "admin"  # Default admin username (can be overridden in terraform.tfvars)
}

variable "jenkins_admin_password" {
  description = "Jenkins admin password (sensitive - set in terraform.tfvars)"  # Admin password for Jenkins login
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
  # Must be set in terraform.tfvars (no default for security)
}

variable "jenkins_github_token" {
  description = "GitHub personal access token for Jenkins PR validation (sensitive - set in terraform.tfvars)"  # GitHub token for PR validation
  type        = string
  sensitive   = true  # Mark as sensitive (value hidden in Terraform output)
  # Must be set in terraform.tfvars (no default for security)
  # Token scopes: repo (full control), admin:repo_hook (webhook management)
}