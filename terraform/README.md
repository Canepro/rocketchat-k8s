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

**Example (placeholders — replace with your actual values):**
```hcl
rocketchat_mongo_uri = "mongodb://rocketchat:CHANGE_ME@mongodb-0.mongodb-svc.rocketchat.svc.cluster.local:27017/rocketchat?authSource=rocketchat&replicaSet=mongodb"
rocketchat_mongo_oplog_uri = "mongodb://admin:CHANGE_ME@mongodb-0.mongodb-svc.rocketchat.svc.cluster.local:27017/local?authSource=admin&replicaSet=mongodb"
mongodb_admin_password = "CHANGE_ME"
mongodb_rocketchat_password = "CHANGE_ME"
mongodb_metrics_endpoint_password = "CHANGE_ME"
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

## State Management (Best Practices for Cloud Shell)

**Recommended:** Use Azure Storage backend for Terraform state with `backend.hcl` configuration file.

### Backend Configuration Structure

This repo uses a **best practice pattern** for Cloud Shell:

1. **`backend.tf`** - Defines backend structure (committed to git)
2. **`backend.hcl.example`** - Template showing required values (committed to git)
3. **`backend.hcl`** - Your actual backend config (gitignored, contains sensitive storage account details)

### Quick Start: First-Time Setup

**Step 1:** Copy the example backend config:

```bash
cd terraform
cp backend.hcl.example backend.hcl
```

**Step 2:** Edit `backend.hcl` with your actual storage account details:

```bash
nano backend.hcl
# Update with your values:
# - resource_group_name
# - storage_account_name
# - container_name
# - key
```

**Step 3:** Initialize Terraform using the helper script:

```bash
./scripts/tf-init.sh
```

Or manually:

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

### Cloud Shell Workflow (Ephemeral Sessions)

Since Cloud Shell sessions are ephemeral, you'll need to recreate `backend.hcl` each session. **Recommended workflow:**

**Option A: Use the helper script (Recommended)**

```bash
# 1. Clone repo (if not already cloned)
git clone <your-repo-url>
cd rocketchat-k8s/terraform

# 2. Create backend.hcl (one-time per session)
cp backend.hcl.example backend.hcl
nano backend.hcl  # Update with your values

# 3. Initialize
./scripts/tf-init.sh

# 4. Use Terraform normally
terraform plan
terraform apply
```

**Option B: Quick inline command (Alternative)**

If you prefer not to use `backend.hcl`, you can use inline backend config:

```bash
terraform init -reconfigure \
  -backend-config="resource_group_name=rg-terraform-state" \
  -backend-config="storage_account_name=tfcaneprostate1" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=aks.terraform.tfstate"
```

**Option C: Cloud Shell alias (Pro-Tip)**

Create a persistent alias in Cloud Shell (survives sessions if you mount clouddrive):

```bash
# Add to ~/.bashrc or ~/clouddrive/.bashrc
echo 'alias tfinit="cd ~/clouddrive/rocketchat-k8s/terraform && cp backend.hcl.example backend.hcl && nano backend.hcl && terraform init -reconfigure -backend-config=backend.hcl"' >> ~/.bashrc
source ~/.bashrc

# Then just type:
tfinit
```

### Benefits of This Approach

✅ **Security**: Backend config (storage account details) never committed to git  
✅ **Flexibility**: Easy to switch between environments  
✅ **Best Practice**: Follows Terraform recommended patterns  
✅ **Cloud Shell Friendly**: Works well with ephemeral sessions  
✅ **State Persistence**: State stored in Azure Storage, survives Cloud Shell sessions  
✅ **State Locking**: Prevents concurrent modifications  
✅ **Versioning**: Azure Storage provides state file versioning and backup

### Important Security Notes

1. **Never commit `backend.hcl`** - It's gitignored for a reason (contains storage account details)
2. **Secure storage account** - Ensure your state storage account has:
   - Encryption at rest enabled (default)
   - Access restricted to authorized users only
   - Consider using Azure Key Vault for state encryption keys
3. **State contains secrets** - Terraform state may contain sensitive values from `terraform.tfvars`
4. **Backend access** - Only authorized users should have access to the storage account container

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
- `backend.tf` - Backend configuration structure (committed)
- `backend.hcl.example` - Backend config template (committed)
- `backend.hcl` - Your backend config (gitignored, never commit)
- `aks.tf` - AKS cluster configuration
- `network.tf` - Networking configuration
- `automation.tf` - Azure Automation for scheduled start/stop
- `keyvault.tf` - Key Vault + UAMI + RBAC (for GitOps secrets)
- `variables.tf` - Input variables
- `outputs.tf` - Output values (Key Vault name, UAMI client ID, etc.)
- `terraform.tfvars.example` - Example variables (safe to commit)
- `terraform.tfvars` - Your actual variables (gitignored, never commit)
- `scripts/tf-init.sh` - Helper script for Cloud Shell initialization

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
