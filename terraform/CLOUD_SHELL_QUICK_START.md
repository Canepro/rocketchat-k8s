# Cloud Shell Quick Start Guide

This guide provides a quick reference for using Terraform in Azure Cloud Shell (ephemeral sessions).

## 🚀 Quick Start (New Cloud Shell Session)

Every time you start a new Cloud Shell session, follow these steps:

### Step 1: Clone/Update Repository

```bash
# If first time, clone the repo
git clone <your-repo-url>
cd rocketchat-k8s/terraform

# OR if repo already exists in clouddrive
cd ~/clouddrive/rocketchat-k8s/terraform
git pull
```

### Step 2: Create Backend Configuration

```bash
# Copy example to actual config (gitignored)
cp backend.hcl.example backend.hcl

# Edit with your storage account details
nano backend.hcl
```

**Update these values in `backend.hcl`:**
```hcl
resource_group_name  = "rg-terraform-state"  # Your resource group
storage_account_name = "tfcaneprostate1"      # Your storage account
container_name       = "tfstate"             # Container name
key                  = "aks.terraform.tfstate"  # State file name
```

### Step 3: Initialize Terraform

```bash
# Use helper script (recommended)
./scripts/tf-init.sh

# OR manually
terraform init -reconfigure -backend-config=backend.hcl
```

### Step 4: Use Terraform

```bash
# Review changes
terraform plan

# Apply changes
terraform apply

# View outputs
terraform output
```

## 📋 Common Commands

### Terraform Operations

```bash
# Initialize (after creating backend.hcl)
terraform init -reconfigure -backend-config=backend.hcl

# Plan (review changes)
terraform plan

# Apply (make changes)
terraform apply

# Apply with auto-approve (skip confirmation)
terraform apply -auto-approve

# Destroy (⚠️ deletes all resources)
terraform destroy

# View outputs
terraform output
terraform output -json > outputs.json
```

### AKS Manual Control (if needed)

```bash
# Start cluster manually
az aks start --resource-group rg-canepro-aks --name aks-canepro

# Stop cluster manually
az aks stop --resource-group rg-canepro-aks --name aks-canepro

# Check cluster status
az aks show --name aks-canepro --resource-group rg-canepro-aks --query "powerState"
```

## 🔧 Pro Tips for Cloud Shell

### 1. Use Cloud Drive for Persistence

Store your repo in `~/clouddrive` to persist across sessions:

```bash
# Clone to clouddrive (persists across sessions)
cd ~/clouddrive
git clone <your-repo-url>
cd rocketchat-k8s/terraform
```

### 2. Create a Persistent Alias

Add to `~/clouddrive/.bashrc` (survives sessions):

```bash
# Add to ~/clouddrive/.bashrc
cat >> ~/clouddrive/.bashrc <<'EOF'

# Terraform shortcuts
alias tfinit='cd ~/clouddrive/rocketchat-k8s/terraform && [ ! -f backend.hcl ] && cp backend.hcl.example backend.hcl && terraform init -reconfigure -backend-config=backend.hcl'
alias tfplan='cd ~/clouddrive/rocketchat-k8s/terraform && terraform plan'
alias tfapply='cd ~/clouddrive/rocketchat-k8s/terraform && terraform apply'
EOF

# Reload
source ~/clouddrive/.bashrc
```

### 3. Store Backend Config in Cloud Drive

Create `backend.hcl` in clouddrive for persistence:

```bash
# Create persistent backend.hcl
cat > ~/clouddrive/terraform-backend.hcl <<'EOF'
resource_group_name  = "rg-terraform-state"
storage_account_name = "tfcaneprostate1"
container_name       = "tfstate"
key                  = "aks.terraform.tfstate"
EOF

# Then symlink or copy each session
cd ~/clouddrive/rocketchat-k8s/terraform
cp ~/clouddrive/terraform-backend.hcl backend.hcl
```

## ⚠️ Important Reminders

1. **`backend.hcl` is gitignored** - Never commit it (contains storage account details)
2. **`terraform.tfvars` is gitignored** - Never commit it (contains secrets)
3. **State is in Azure Storage** - Persists across Cloud Shell sessions
4. **Re-initialize each session** - Run `terraform init` after creating `backend.hcl`

## 🆘 Troubleshooting

### "Backend configuration changed"

```bash
# Re-initialize with reconfigure flag
terraform init -reconfigure -backend-config=backend.hcl
```

### "Backend state not found"

Check your `backend.hcl` values match your actual storage account:
- Resource group name
- Storage account name
- Container name
- Key (state file path)

### "Authentication failed"

```bash
# Re-authenticate
az login
az account set --subscription <subscription-id>
```

### "Permission denied" on scripts

```bash
# Make script executable
chmod +x scripts/tf-init.sh
```

## 📚 Related Documentation

- Full setup: `README.md`
- Variables reference: `variables.tf`
- Example config: `terraform.tfvars.example`
- Backend example: `backend.hcl.example`
