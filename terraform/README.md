# Terraform Configuration for Rocket.Chat AKS Deployment

This directory contains Terraform configuration for provisioning Azure infrastructure for Rocket.Chat on AKS, including Key Vault for GitOps secrets management.

## ⚠️ Important

The main AKS stack uses an **Azure Storage remote backend** authenticated through Azure CLI and Microsoft Entra ID. Only the small bootstrap stack in `terraform/bootstrap/` uses local state, because it creates the backend itself.

## 🚀 Quick Reference: Authenticated Machine Setup

**First time setup:**
```bash
git clone https://github.com/Canepro/rocketchat-k8s.git
cd rocketchat-k8s/terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw backend_hcl > ../backend.hcl
cd ../
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
terraform init -reconfigure -backend-config=backend.hcl
```

**Subsequent sessions on the same machine:**
```bash
cd /home/vincent/src/rocketchat-k8s/terraform
git pull
cd bootstrap
terraform init
terraform output -raw backend_hcl > ../backend.hcl
cd ..
terraform init -reconfigure -backend-config=backend.hcl
```

**See [`REMOTE_BACKEND_QUICK_START.md`](REMOTE_BACKEND_QUICK_START.md) for the detailed backend workflow.**

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.8 installed on the machine you use for applies
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

### Plan stability (human operator vs Jenkins identity)

This repo may be planned/applied by different Azure identities (for example, your interactive Azure CLI login vs Jenkins Workload Identity).

To avoid noisy plans (or destructive replacements) caused solely by “who ran Terraform”, the Key Vault role assignment that grants the Terraform runner permissions is configured to **ignore changes to `principal_id`**.

Practical impact:
- ✅ prevents “replace role assignment” churn when switching runners
- ✅ keeps Key Vault RBAC mode stable for ESO/Jenkins
- ⚠️ if you intentionally want a new identity to have the same Key Vault role, grant it explicitly (don’t rely on Terraform drift)

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
- `rocketchat-observability-username`
- `rocketchat-observability-password`
- `jenkins-admin-username`
- `jenkins-admin-password`
- `jenkins-github-token`

### Secret Protection (ignore_changes)

**Important:** All secret resources use `lifecycle { ignore_changes = [value] }` to prevent Terraform from overwriting secrets when `terraform.tfvars` has placeholder values.

**What this means:**
- ✅ Terraform creates the secret resources initially
- ✅ Terraform won't update secret values if `terraform.tfvars` has placeholders (e.g., `"CHANGE_ME"`)
- ✅ Secrets can be updated manually via Azure CLI/Portal without Terraform interference
- ✅ Prevents accidental overwrites of real secrets

**To update a secret value:**
1. Update it directly in Azure Key Vault (CLI/Portal)
2. Or temporarily remove `ignore_changes`, update `terraform.tfvars` with real value, apply, then restore `ignore_changes`

**Security Note:** Secret values are marked as `sensitive = true` in Terraform, so they won't appear in plan/apply output. However, they will be stored in Terraform state. Use a secure backend (Azure Storage) and ensure state access is restricted.

## State Management

The repo uses a two-step backend pattern:

1. `terraform/bootstrap/` creates the Azure Storage backend in your personal subscription.
2. `terraform/` stores the main AKS state in that backend using `backend.hcl`.

### Why this pattern

- avoids the backend chicken-and-egg problem
- keeps the main stack on remote state with locking and versioning
- uses Azure AD auth instead of storage account keys
- keeps backend details out of Git

### Files

1. `bootstrap/main.tf` and related files: create the state storage account and container
2. `backend.tf`: partial `azurerm` backend block for the main stack
3. `backend.hcl.example`: template for the local-only backend config
4. `backend.hcl`: generated locally from bootstrap outputs, never committed

### First-time setup

```bash
cd /home/vincent/src/rocketchat-k8s/terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw backend_hcl > ../backend.hcl

cd ../
terraform init -reconfigure -backend-config=backend.hcl
```

If you already created local state for the main stack and want to move it into the backend:

```bash
terraform init -reconfigure -backend-config=backend.hcl -migrate-state
```

### What the bootstrap stack creates

- dedicated resource group for state
- `StorageV2` account with `Standard_LRS`
- private blob container
- blob versioning and soft delete
- `Storage Blob Data Contributor` for the current Azure principal
- optional `Storage Blob Data Contributor` assignments for Jenkins or other workload identities
- OAuth preferred for backend access; shared keys remain enabled for AzureRM provider compatibility

### Security notes

1. Never commit `backend.hcl`
2. Never commit `.tfstate` or state backups
3. Terraform state contains secrets, so restrict access to the storage account
4. Use Azure CLI / Entra ID authentication for backend access instead of storage keys

## Cost Optimization: Automated Cluster Scheduling

The AKS cluster uses **Azure Automation** to automatically start and stop the cluster on a schedule, significantly reducing costs.

### Current Recommended Schedule (2026-03-18)

- **Start Time**: 13:30 (1:30 PM) on weekdays
- **Stop Time**: 16:15 (4:15 PM) on weekdays
- **Weekends**: Cluster stays off
- **Runtime**: ~2.75 hours/day × 5 weekdays = ~13.75 hours/week = ~55 hours/month
- **Reasoning**: Leaves ~30 minutes for startup and ~15 minutes for shutdown while keeping the cluster available for a 14:00-16:00 work window

### Configuration

Schedule is managed via Terraform variables in `terraform.tfvars`:

```hcl
enable_auto_shutdown = true
shutdown_timezone    = "Europe/London"
shutdown_time        = "16:15"  # 4:15 PM stop
startup_time         = "13:30"  # 1:30 PM start
```

**Terraform Resources:**
- `azurerm_automation_account` - Automation account for scheduling
- `azurerm_automation_schedule` - Start and stop schedules (weekdays only)
- `azurerm_automation_runbook` - PowerShell runbooks to start/stop AKS
- `azurerm_automation_job_schedule` - Links schedules to runbooks

### Manual Override

If you need the cluster during off-hours:

```bash
# Start cluster manually
az aks start --resource-group rg-canepro-aks --name aks-canepro

# Stop cluster manually
az aks stop --resource-group rg-canepro-aks --name aks-canepro
```

**Note:** Schedules use `lifecycle { ignore_changes = [start_time] }` to prevent Terraform from updating schedule times on every run. To update schedules, temporarily remove `ignore_changes`, update variables, apply, then restore `ignore_changes`.

### Cost Savings

- **Previous schedule** (08:30-23:00): ~72.5 hours/week = ~290 hours/month
- **Later evening schedule** (16:00-23:00): ~35 hours/week = ~140 hours/month
- **Current recommended schedule** (13:30-16:15): ~13.75 hours/week = ~55 hours/month
- **Savings vs 16:00-23:00**: ~61% reduction in runtime hours

## Jenkins + Terraform (CI Validation)

Jenkins is configured to run Terraform validation on every push/PR using **Azure Workload Identity**:

### Current CI Pipeline Stages (All Enabled ✅)
1. **Setup**: Installs Terraform in the Azure CLI container
2. **Azure Login**: Authenticates via Workload Identity (federated token)
3. **Terraform Format**: `terraform fmt -check -recursive`
4. **Terraform Validate**: `terraform init` + `terraform validate`
5. **Terraform Plan**: `terraform plan` against the Azure Storage remote backend

### How It Works
- **Authentication**: Uses the `jenkins` service account with federated credentials to the ESO managed identity
- **State Backend**: Reads/writes to the bootstrap-created Azure Storage account using Azure AD auth
- **Variables**: Uses `terraform.tfvars.example` for CI (placeholder values, no real secrets)
- **Plan Output**: Archived as build artifact for review

### Permissions Required (Already Configured)
The ESO identity has these roles for Jenkins terraform validation:
- `Reader` on subscription (read Azure resources)
- `Storage Blob Data Contributor` on the Terraform backend storage account (read/write/lock state)
- `Azure Kubernetes Service Cluster User Role` on AKS (list cluster credentials)

See `.jenkins/WORKLOAD_IDENTITY_SETUP.md` for full details.

### Terraform Apply from Jenkins
**Not currently enabled.** To enable `terraform apply`:
1. Grant `Contributor` role on the resource group (instead of just `Reader`)
2. Add manual approval step in the pipeline
3. Implement secure handling of real `terraform.tfvars` (e.g., fetch from Key Vault)

For now, `terraform apply` should be run interactively by you from your authenticated machine.

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
- `backend.tf` - Partial remote backend configuration (committed)
- `backend.hcl.example` - Backend config template (committed)
- `backend.hcl` - Your local backend config (gitignored, never commit)
- `bootstrap/` - Bootstrap stack that creates the Azure Storage backend
- `aks.tf` - AKS cluster configuration
- `network.tf` - Networking configuration
- `automation.tf` - Azure Automation for scheduled start/stop
- `keyvault.tf` - Key Vault + UAMI + RBAC (for GitOps secrets)
- `variables.tf` - Input variables
- `outputs.tf` - Output values (Key Vault name, UAMI client ID, etc.)
- `terraform.tfvars.example` - Example variables (safe to commit)
- `terraform.tfvars` - Your actual variables (gitignored, never commit)
- `scripts/tf-init.sh` - Helper script for backend initialization
- `REMOTE_BACKEND_QUICK_START.md` - Quick reference guide for the backend workflow

## Security Notes

1. **Never commit `terraform.tfvars`** - It contains sensitive secret values (gitignored)
2. **Never commit `.tfstate` files** - They contain sensitive resource IDs and secret values (gitignored)
3. **Use secure backend** - Store state in Azure Storage with proper access controls and Azure AD auth
4. **Secret values in state** - Terraform state will contain secret values. Ensure backend storage has:
   - Encryption at rest enabled
   - Access restricted to authorized users only
   - Consider using Azure Key Vault for state encryption keys
5. **RBAC mode** - Key Vault uses RBAC (not access policies) for better security
6. **Sensitive variables** - All secret variables are marked `sensitive = true` to prevent output in logs
