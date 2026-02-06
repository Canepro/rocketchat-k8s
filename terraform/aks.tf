# Terraform Configuration: AKS Cluster
# This file provisions the Azure Kubernetes Service (AKS) cluster for Rocket.Chat.
# The cluster includes: Node pool, networking, RBAC, and identity configuration.
# See VERSIONS.md for Kubernetes version tracking (managed by AKS).

# Get current client configuration (for RBAC and authentication)
# This data source retrieves current Azure client configuration (tenant ID, object ID, etc.)
# Used for RBAC role assignments and authentication
data "azurerm_client_config" "current" {}

# AKS Cluster: Main Kubernetes cluster resource
# This resource creates the AKS cluster with all required configuration.
# AKS Cluster
# tfsec:ignore:AVD-AZU-0041 - Personal/training environment; public API server exposure accepted.
# tfsec:ignore:AVD-AZU-0040 - Azure Monitor (OMS agent) intentionally disabled; Prometheus Agent is used instead (avoid duplicate telemetry/cost).
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name                                             # Cluster name (from variables.tf, default: "aks-canepro")
  location            = azurerm_resource_group.main.location                         # Azure region (from resource group)
  resource_group_name = azurerm_resource_group.main.name                             # Resource group (from main.tf)
  dns_prefix          = var.dns_prefix                                               # DNS prefix for cluster FQDN (from variables.tf, default: "aks-canepro")
  kubernetes_version  = var.kubernetes_version != "" ? var.kubernetes_version : null # Kubernetes version (empty = latest)

  # Required for Azure Workload Identity (used by External Secrets Operator)
  # Workload Identity allows Kubernetes ServiceAccounts to authenticate to Azure services
  # This is used by External Secrets Operator to authenticate to Azure Key Vault
  oidc_issuer_enabled       = true # Enable OIDC issuer (required for Workload Identity)
  workload_identity_enabled = true # Enable Workload Identity (for ESO Key Vault authentication)

  # Enable System-Assigned Managed Identity (for Jenkins Azure access)
  # System-Assigned Managed Identity allows the AKS cluster to authenticate to Azure services
  # This can be used by Jenkins (or other services) running in the cluster for Azure access
  identity {
    type = "SystemAssigned" # System-Assigned Managed Identity (managed by Azure)
  }

  # Enable RBAC (Role-Based Access Control)
  # RBAC is required for proper Kubernetes security and is required for many features
  role_based_access_control_enabled = true # Enable RBAC (required for AKS)

  # API server access profile: Controls which IP addresses can access the Kubernetes API server
  # Empty authorized_ip_ranges means allow all IPs (less secure but more flexible)
  api_server_access_profile {
    authorized_ip_ranges                = []    # Allow all IPs (can restrict to specific IPs for security)
    virtual_network_integration_enabled = false # Explicit default to keep plans stable
  }

  # Default node pool: Worker nodes for running Kubernetes pods
  # Default node pool
  default_node_pool {
    name                        = "system"                  # Node pool name (must be lowercase, alphanumeric, max 12 chars)
    node_count                  = var.node_count            # Number of nodes (from variables.tf, default: 2)
    vm_size                     = var.vm_size               # VM size (from variables.tf, default: "Standard_D4as_v5")
    os_disk_size_gb             = 30                        # OS disk size in GB (minimum 30GB for AKS)
    type                        = "VirtualMachineScaleSets" # Node pool type (VMSS for scalability)
    vnet_subnet_id              = azurerm_subnet.aks.id     # Subnet for nodes (from network.tf)
    temporary_name_for_rotation = "tempnodepool"            # Required when updating vm_size (enables rolling node updates)

    # Labels and taints: Kubernetes node labels and taints
    # Labels help identify node roles and capabilities
    node_labels = {
      "node.kubernetes.io/role" = "worker" # Node role label (used for scheduling)
    }

    tags = var.tags # Tags for node pool VMs (from variables.tf)
  }

  # Network configuration: Kubernetes networking setup
  # Network configuration
  network_profile {
    network_plugin    = "kubenet"  # Network plugin (kubenet for basic networking, azure CNI for advanced)
    network_policy    = "calico"   # Network policy for kubenet (enabled; no effect until policies are applied)
    load_balancer_sku = "standard" # LoadBalancer SKU (standard for production, basic for testing)
    # Service CIDR must not overlap with VNet (10.0.0.0/16) or subnet (10.0.1.0/24)
    # Service CIDR: IP range for Kubernetes Services (ClusterIP, LoadBalancer, etc.)
    service_cidr   = "10.0.2.0/24" # Service CIDR (must not overlap with VNet or subnet)
    dns_service_ip = "10.0.2.10"   # DNS service IP (must be within service_cidr and not .1)
    # Pod CIDR for kubenet (each node gets a /24 from this range)
    # Pod CIDR: IP range for Kubernetes Pods (kubenet uses this for pod networking)
    pod_cidr = "10.244.0.0/16" # Pod CIDR (must not overlap with VNet, subnet, or service_cidr)
  }

  # Enable Azure Policy (optional)
  # Azure Policy allows you to enforce governance policies on Kubernetes resources
  azure_policy_enabled = false # Disable Azure Policy (not needed for this setup)

  # OMS Agent is not enabled (we use Prometheus Agent for monitoring)
  # OMS Agent is Azure's built-in monitoring agent (we use Prometheus Agent instead)
  # When oms_agent block is omitted, it defaults to disabled
  # See ops/manifests/prometheus-agent-deployment.yaml for Prometheus Agent deployment

  tags = var.tags # Tags for AKS cluster (from variables.tf)

  # Lifecycle configuration: Prevent Terraform from modifying certain resources
  # We are intentionally not managing certain AKS defaults in this repo right now.
  # This prevents Terraform from making in-place changes during state recovery when the
  # existing cluster was created previously and has provider-managed defaults.
  lifecycle {
    ignore_changes = [
      default_node_pool[0].upgrade_settings, # Ignore upgrade settings (managed by AKS automatically)
      # Azure doesn't persist api_server_access_profile defaults, so it causes perpetual diffs.
      api_server_access_profile,
    ]
  }
}
