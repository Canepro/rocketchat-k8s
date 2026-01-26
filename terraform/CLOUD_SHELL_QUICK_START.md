# Cloud Shell Quick Start Guide

This guide provides a quick reference for using Terraform in Azure Cloud Shell (ephemeral sessions).

## 🚀 Quick Start (New Cloud Shell Session)

Every time you start a new Cloud Shell session, follow these steps:

### Step 1: Clone Repository to Cloud Drive (First Time Only)

**Important:** Clone to `~/clouddrive` so it persists across Cloud Shell sessions.

```bash
cd ~/clouddrive
git clone https://github.com/Canepro/rocketchat-k8s.git
cd rocketchat-k8s/terraform
```

**For subsequent sessions**, the repo is already in `~/clouddrive`:
```bash
cd ~/clouddrive/rocketchat-k8s/terraform
git pull  # Update to latest changes
```

### Step 2: Create Backend Configuration

Create `backend.hcl` with your storage account details (gitignored, won't be committed):

```bash
cat <<EOF > backend.hcl
resource_group_name  = "rg-terraform-state"
storage_account_name = "tfcaneprostate1"
container_name       = "tfstate"
key                  = "aks.terraform.tfstate"
EOF
```

**Note:** `backend.hcl` is gitignored. You'll need to recreate it each Cloud Shell session (or store it in `~/clouddrive` separately and copy it).

### Step 3: Initialize Terraform

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

This connects Terraform to your Azure Storage backend where state is stored.

### Step 4: Configure Variables (First Time Only)

```bash
# Copy example to actual config (gitignored)
cp terraform.tfvars.example terraform.tfvars

# Edit with your actual values (secrets, schedule times, etc.)
nano terraform.tfvars
```

**Important:** `terraform.tfvars` is gitignored and contains sensitive values. Never commit it.

### Step 5: Use Terraform

```bash
# Review changes
terraform plan

# Apply changes (if plan looks good)
terraform apply

# View outputs
terraform output
```

## 🔄 Returning to Cloud Shell (Subsequent Sessions)

If you've already set up the repo in `~/clouddrive`, you only need:

```bash
# 1. Navigate to terraform directory
cd ~/clouddrive/rocketchat-k8s/terraform

# 2. Pull latest changes (optional)
git pull

# 3. Recreate backend.hcl (required each session)
cat <<EOF > backend.hcl
resource_group_name  = "rg-terraform-state"
storage_account_name = "tfcaneprostate1"
container_name       = "tfstate"
key                  = "aks.terraform.tfstate"
EOF

# 4. Re-initialize Terraform
terraform init -reconfigure -backend-config=backend.hcl

# 5. Use Terraform
terraform plan
terraform apply
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

### 2. Store Backend Config Template in Cloud Drive

Since `backend.hcl` needs to be recreated each session, you can store a template in clouddrive:

```bash
# Create persistent template (one-time)
cat > ~/clouddrive/terraform-backend.hcl <<'EOF'
resource_group_name  = "rg-terraform-state"
storage_account_name = "tfcaneprostate1"
container_name       = "tfstate"
key                  = "aks.terraform.tfstate"
EOF

# Then each session, copy it:
cd ~/clouddrive/rocketchat-k8s/terraform
cp ~/clouddrive/terraform-backend.hcl backend.hcl
terraform init -reconfigure -backend-config=backend.hcl
```

### 3. Create a Persistent Alias

Add to `~/clouddrive/.bashrc` (survives sessions):

```bash
# Add to ~/clouddrive/.bashrc
cat >> ~/clouddrive/.bashrc <<'EOF'

# Terraform shortcuts
alias tfinit='cd ~/clouddrive/rocketchat-k8s/terraform && cat <<EOFHCL > backend.hcl
resource_group_name  = "rg-terraform-state"
storage_account_name = "tfcaneprostate1"
container_name       = "tfstate"
key                  = "aks.terraform.tfstate"
EOFHCL
terraform init -reconfigure -backend-config=backend.hcl'
alias tfplan='cd ~/clouddrive/rocketchat-k8s/terraform && terraform plan'
alias tfapply='cd ~/clouddrive/rocketchat-k8s/terraform && terraform apply'
EOF

# Reload
source ~/clouddrive/.bashrc
```

Then you can just type `tfinit` to set up everything.

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
