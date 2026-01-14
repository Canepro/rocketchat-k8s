# Terraform Configuration for AKS

This directory contains Terraform configuration to provision the Azure Kubernetes Service (AKS) cluster for RocketChat.

## Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI installed and authenticated (`az login`)
- Terraform installed (>= 1.0)

## Setup

1. **Copy example variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values:**
   - Resource group name
   - Location (e.g., `uksouth`)
   - Cluster name
   - Node count and VM size

3. **Create Azure Storage Account for Terraform state (recommended):**
   ```bash
   az storage account create \
     --name tfstate<unique-id> \
     --resource-group rg-terraform-state \
     --location uksouth \
     --sku Standard_LRS
   
   az storage container create \
     --name tfstate \
     --account-name tfstate<unique-id>
   ```

4. **Update `main.tf` backend configuration:**
   - Uncomment the `backend "azurerm"` block
   - Update storage account name and resource group

## Usage

### From Azure Cloud Shell

1. **Clone repository:**
   ```bash
   git clone https://github.com/Canepro/rocketchat-k8s.git
   cd rocketchat-k8s/terraform
   ```

2. **Checkout migration branch:**
   ```bash
   git checkout aks-migration
   ```

3. **Create terraform.tfvars:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

4. **Initialize Terraform:**
   ```bash
   terraform init
   ```

5. **Plan deployment:**
   ```bash
   terraform plan -out=tfplan
   ```

6. **Apply configuration:**
   ```bash
   terraform apply tfplan
   ```

7. **Get AKS credentials:**
   ```bash
   az aks get-credentials \
     --resource-group $(terraform output -raw resource_group_name) \
     --name $(terraform output -raw cluster_name) \
     --overwrite-existing
   ```

8. **Verify cluster:**
   ```bash
   kubectl get nodes
   ```

## Outputs

After deployment, use `terraform output` to get:
- Resource group name
- Cluster name
- Cluster FQDN
- Node resource group (for auto-shutdown configuration)
- Managed Identity Principal ID (for Jenkins)

## Cost Optimization

- Worker nodes use `Standard_B2s` (2 vCPU, 4GB RAM)
- Auto-shutdown can be configured for weekends
- Control plane is free (managed by Azure)

## Notes

- Terraform state should be stored in Azure Storage Account for persistence
- Cloud Shell storage is temporary and state will be lost between sessions
- Managed Identity is enabled for Jenkins Azure access (no service principal needed)
