variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-rocketchat-aks"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "uksouth"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-rocketchat"
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
  default     = "aks-rocketchat"
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
    Project     = "RocketChat"
  }
}
