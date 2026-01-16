# Get current client configuration (for RBAC)
data "azurerm_client_config" "current" {}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version != "" ? var.kubernetes_version : null

  # Required for Azure Workload Identity (used by External Secrets Operator)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Enable System-Assigned Managed Identity (for Jenkins Azure access)
  identity {
    type = "SystemAssigned"
  }

  # Enable RBAC
  role_based_access_control_enabled = true

  # API server authorized IP ranges (empty = allow all)
  # Note: This uses deprecated syntax because api_server_access_profile block
  # causes perpetual drift (azurerm provider bug). Will migrate to new syntax
  # when upgrading to provider v4.0.
  api_server_authorized_ip_ranges = []

  # Default node pool
  default_node_pool {
    name                         = "system"
    node_count                   = var.node_count
    vm_size                      = var.vm_size
    os_disk_size_gb              = 30
    type                         = "VirtualMachineScaleSets"
    enable_auto_scaling          = false
    vnet_subnet_id               = azurerm_subnet.aks.id
    temporary_name_for_rotation  = "tempnodepool"  # Required when updating vm_size

    # Labels and taints
    node_labels = {
      "node.kubernetes.io/role" = "worker"
    }

    tags = var.tags
  }

  # Network configuration
  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    # Service CIDR must not overlap with VNet (10.0.0.0/16) or subnet (10.0.1.0/24)
    service_cidr   = "10.0.2.0/24"
    dns_service_ip = "10.0.2.10"
    # Pod CIDR for kubenet (each node gets a /24 from this range)
    pod_cidr = "10.244.0.0/16"
  }

  # Enable Azure Policy (optional)
  azure_policy_enabled = false

  # OMS Agent is not enabled (we use Prometheus Agent for monitoring)
  # When oms_agent block is omitted, it defaults to disabled

  tags = var.tags

  # We are intentionally not managing certain AKS defaults in this repo right now.
  # This prevents Terraform from making in-place changes during state recovery when the
  # existing cluster was created previously and has provider-managed defaults.
  lifecycle {
    ignore_changes = [
      default_node_pool[0].upgrade_settings,
    ]
  }
}
