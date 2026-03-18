# Remote Backend Quick Start Guide

This guide assumes the main AKS stack uses an Azure Storage remote backend authenticated through Azure CLI and Microsoft Entra ID.
You can run this from any authenticated machine. Cloud Shell is optional, not required.

## First-time setup

```bash
cd /home/vincent/src/rocketchat-k8s/terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw backend_hcl > ../backend.hcl
cd ../
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
terraform init -reconfigure -backend-config=backend.hcl
```

## Subsequent sessions

```bash
cd /home/vincent/src/rocketchat-k8s
git pull
cd terraform/bootstrap
terraform init
terraform output -raw backend_hcl > ../backend.hcl
cd ../
terraform init -reconfigure -backend-config=backend.hcl
```

## Day-to-day commands

```bash
cd /home/vincent/src/rocketchat-k8s/terraform
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

## Notes

- `backend.hcl` is gitignored and should never be committed.
- `terraform.tfvars` is gitignored and should never be committed.
- The bootstrap stack keeps its own local state; the main AKS stack uses Azure Storage remote state.
- If Jenkins CI also needs backend access, grant its Azure principal `Storage Blob Data Contributor` through the bootstrap stack.
- Backend auth should use Azure AD or OIDC even though shared keys remain enabled for provider compatibility.
- If the backend configuration changes, rerun:

```bash
terraform init -reconfigure -backend-config=backend.hcl
```
