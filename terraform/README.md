# Terraform Configuration for Rocket.Chat AKS Deployment

This directory contains Terraform configuration for provisioning Azure infrastructure for Rocket.Chat on AKS, including Key Vault for GitOps secrets management.

## ⚠️ Important: Cloud Shell Only

**Per migration plan restrictions**, Terraform applies must be run **only from Azure Portal / Cloud Shell on your work machine**. Do not run Terraform from other machines or CI/CD pipelines.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.0 installed in Cloud Shell
- Appropriate Azure permissions (Contributor or higher on target subscription/resource group)

## Quick Start

### 1. Copy example variables file

```bash
cp terraform.tfvars.example terraform.tfvars
```

**Note:** `terraform.tfvars` is gitignored and should **never** be committed (it may contain sensitive values).

### 2. Edit `terraform.tfvars` (REQUIRED for secrets)

**Copy the example and fill in secret values:**

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your actual secret values
```

**Required secret variables** (fill these in `terraform.tfvars`):
- `rocketchat_mongo_uri` - MongoDB connection string
- `rocketchat_mongo_oplog_uri` - MongoDB oplog connection string
- `mongodb_admin_password` - MongoDB admin password
- `mongodb_rocketchat_password` - MongoDB rocketchat user password
- `mongodb_metrics_endpoint_password` - MongoDB metrics password

**Example:**
```hcl
rocketchat_mongo_uri = "mongodb://rocketchat:rocketchatroot@mongodb-0.mongodb-svc.rocketchat.svc.cluster.local:27017/rocketchat?authSource=rocketchat&replicaSet=mongodb"
rocketchat_mongo_oplog_uri = "mongodb://admin:rocketchatroot@mongodb-0.mongodb-svc.rocketchat.svc.cluster.local:27017/local?authSource=admin&replicaSet=mongodb"
mongodb_admin_password = "rocketchatroot"
mongodb_rocketchat_password = "rocketchatroot"
mongodb_metrics_endpoint_password = "rocketchatroot"
```

**⚠️ CRITICAL:** `terraform.tfvars` is gitignored. Never commit it or push it to git.

### 3. Initialize Terraform

```bash
cd terraform
terraform init
```

### 4. Review the plan

```bash
terraform plan
```

This shows what will be created:
- Resource Group
- AKS Cluster (if `aks.tf` is included)
- Azure Key Vault
- User Assigned Managed Identity (UAMI) for External Secrets Operator
- RBAC role assignments (UAMI → Key Vault Secrets User)
- **Key Vault Secrets** (from `terraform.tfvars` values)

**Important:** Terraform **DOES** create secret values in Key Vault (via `terraform.tfvars`). Ensure `terraform.tfvars` is gitignored and never committed.

### 5. Apply

```bash
terraform apply
```

### 6. Capture outputs

```bash
terraform output -json > /tmp/terraform-outputs.json
cat /tmp/terraform-outputs.json
```

**Record these values** (needed for GitOps configuration):
- `key_vault_name` → Update `ops/secrets/clustersecretstore-azure-keyvault.yaml`
- `eso_identity_client_id` → Update `GrafanaLocal/argocd/applications/aks-rocketchat-external-secrets.yaml`
- `azure_tenant_id` → Update `ops/secrets/clustersecretstore-azure-keyvault.yaml`

## Key Vault Configuration

The `keyvault.tf` file provisions:

- **Azure Key Vault** with RBAC mode (recommended over access policies)
- **User Assigned Managed Identity** for External Secrets Operator
- **RBAC role assignment**: UAMI gets "Key Vault Secrets User" role (read secrets)

**Network access:** Defaults to `Allow` (public). To restrict:
- Set `key_vault_network_default_action = "Deny"` in `terraform.tfvars`
- Add `network_acls` rules in `keyvault.tf` for specific IPs/VNets

## Secret Values (Created by Terraform)

**Secret values ARE created by Terraform** from variables in `terraform.tfvars` (gitignored).

The `keyvault.tf` file includes `azurerm_key_vault_secret` resources that create:
- `rocketchat-mongo-uri`
- `rocketchat-mongo-oplog-uri`
- `rocketchat-mongodb-admin-password`
- `rocketchat-mongodb-rocketchat-password`
- `rocketchat-mongodb-metrics-endpoint-password`

**Security Note:** Secret values are marked as `sensitive = true` in Terraform, so they won't appear in plan/apply output. However, they will be stored in Terraform state. Use a secure backend (Azure Storage) and ensure state access is restricted.

### Alternative: Populate Secrets Manually (Future Reference)

If you prefer **not** to store secret values in Terraform state, you can:
1. Remove the `azurerm_key_vault_secret` resources from `keyvault.tf`
2. Populate secrets manually via Cloud Shell after Terraform apply:

```bash
az keyvault secret set --vault-name "<key-vault-name>" \
  --name "rocketchat-mongo-uri" --value "<connection-string>"
# ... etc
```

This approach keeps secret values out of Terraform state entirely, but requires manual steps after infrastructure provisioning.

## State Management

**Recommended:** Use Azure Storage backend for Terraform state.

This repo includes an empty backend block in `terraform/main.tf`:

```hcl
terraform {
  backend "azurerm" {}
}
```

Provide the real backend values at init-time via a local `backend.hcl` (gitignored):

```bash
cat > backend.hcl <<'EOF'
resource_group_name  = "rg-terraform-state"
storage_account_name = "tfcaneprostate1"
container_name       = "tfstate"
key                  = "aks.terraform.tfstate"
EOF

terraform init -reconfigure -backend-config=backend.hcl
```

This ensures:
- State is stored securely in Azure
- State can be shared across Cloud Shell sessions
- State is versioned and backed up

**Important:** Even with backend, ensure state backend storage account has proper access controls.

## Jenkins + Terraform (future)

To keep GitOps principles intact:
- Jenkins can run `terraform fmt`, `terraform validate`, and `terraform plan` as PR checks.
- Jenkins should not run `terraform apply` unless the organization explicitly changes the Cloud Shell restriction and you implement manual approvals + least-privilege Azure auth + secure handling of `terraform.tfvars` and state.

## Destroying Resources

**⚠️ Warning:** Destroying will delete the Key Vault and all secrets inside it.

```bash
terraform destroy
```

If `key_vault_purge_protection = true`, you may need to manually disable purge protection first:

```bash
az keyvault update --name "<key-vault-name>" --enable-purge-protection false
```

## Files

- `main.tf` - Provider configuration, resource group
- `aks.tf` - AKS cluster (if included)
- `network.tf` - Networking (if included)
- `keyvault.tf` - Key Vault + UAMI + RBAC (for GitOps secrets)
- `variables.tf` - Input variables
- `outputs.tf` - Output values (Key Vault name, UAMI client ID, etc.)
- `terraform.tfvars.example` - Example variables (safe to commit)
- `terraform.tfvars` - Your actual variables (gitignored, never commit)

## Security Notes

1. **Never commit `terraform.tfvars`** - It contains sensitive secret values (gitignored)
2. **Never commit `.tfstate` files** - They contain sensitive resource IDs and secret values (gitignored)
3. **Use secure backend** - Store state in Azure Storage with proper access controls and encryption
4. **Secret values in state** - Terraform state will contain secret values. Ensure backend storage has:
   - Encryption at rest enabled
   - Access restricted to authorized users only
   - Consider using Azure Key Vault for state encryption keys
5. **RBAC mode** - Key Vault uses RBAC (not access policies) for better security
6. **Sensitive variables** - All secret variables are marked `sensitive = true` to prevent output in logs
