# Get current client configuration (for RBAC)
data "azurerm_client_config" "current" {}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version != "" ? var.kubernetes_version : null

  # Enable System-Assigned Managed Identity (for Jenkins Azure access)
  identity {
    type = "SystemAssigned"
  }

  # Enable RBAC
  role_based_access_control_enabled = true

  # Default node pool
  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.vm_size
    os_disk_size_gb     = 30
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = false
    vnet_subnet_id      = azurerm_subnet.aks.id

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
  }

  # Enable Azure Policy (optional)
  azure_policy_enabled = false

  # OMS Agent is not enabled (we use Prometheus Agent for monitoring)
  # When oms_agent block is omitted, it defaults to disabled

  tags = var.tags
}
