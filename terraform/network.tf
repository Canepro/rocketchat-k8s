# Terraform Configuration: Azure Networking for AKS
# This file provisions Azure networking infrastructure for the AKS cluster.
# It includes: Virtual Network, Subnet, and Network Security Group (NSG).
# Network configuration ensures proper isolation and security for AKS nodes.

# Virtual Network for AKS: Container network for all AKS resources
# Virtual Network for AKS
resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_name}-vnet"  # VNet name (from variables.tf, e.g., "aks-canepro-vnet")
  address_space       = ["10.0.0.0/16"]  # VNet address space (/16 provides 65536 IPs)
  location            = azurerm_resource_group.main.location  # Azure region (from resource group)
  resource_group_name = azurerm_resource_group.main.name  # Resource group (from main.tf)

  tags = var.tags  # Tags for VNet (from variables.tf)
}

# Subnet for AKS nodes: Network segment for AKS worker nodes
# Subnet for AKS nodes
resource "azurerm_subnet" "aks" {
  name                 = "${var.cluster_name}-subnet"  # Subnet name (from variables.tf, e.g., "aks-canepro-subnet")
  resource_group_name  = azurerm_resource_group.main.name  # Resource group (from main.tf)
  virtual_network_name = azurerm_virtual_network.main.name  # VNet name (from VNet resource above)
  address_prefixes     = ["10.0.1.0/24"]  # Subnet address space (/24 provides 256 IPs, must be within VNet)
}

# Network Security Group (optional, for additional security rules)
# NSG provides subnet-level firewall rules for inbound/outbound traffic.
# Network Security Group (optional, for additional security rules)
resource "azurerm_network_security_group" "aks" {
  name                = "${var.cluster_name}-nsg"  # NSG name (from variables.tf, e.g., "aks-canepro-nsg")
  location            = azurerm_resource_group.main.location  # Azure region (from resource group)
  resource_group_name = azurerm_resource_group.main.name  # Resource group (from main.tf)

  # Security rule: Allow HTTP and HTTPS traffic from Internet
  # This rule allows external traffic to reach LoadBalancer services (Traefik ingress controller)
  security_rule {
    name                       = "AllowHttpHttps"  # Rule name (for identification)
    priority                   = 1000  # Rule priority (lower number = higher priority, 100-4096)
    direction                  = "Inbound"  # Traffic direction (Inbound = from Internet to cluster)
    access                     = "Allow"  # Access action (Allow = permit traffic)
    protocol                   = "Tcp"  # Protocol (Tcp, Udp, Icmp, etc.)
    source_port_range          = "*"  # Source port (any port)
    destination_port_ranges    = ["80", "443"]  # Destination ports (HTTP=80, HTTPS=443)
    source_address_prefix      = "Internet"  # Source address (Internet = any IP)
    destination_address_prefix = "*"  # Destination address (any IP in subnet)
  }

  tags = var.tags  # Tags for NSG (from variables.tf)
}

# Associate NSG with subnet: Apply NSG rules to AKS subnet
# This association applies the NSG security rules to the AKS subnet.
# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id  # Subnet resource ID (from subnet resource above)
  network_security_group_id = azurerm_network_security_group.aks.id  # NSG resource ID (from NSG resource above)
}
