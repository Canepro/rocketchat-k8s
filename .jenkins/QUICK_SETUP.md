# Azure Backend Setup for Jenkins Terraform Validation

This repo's Jenkins Terraform validation uses Azure Workload Identity and the Azure Storage remote backend. It does not require storage account keys.

## Required Jenkins environment

The AKS agent pod or Jenkins job must provide:

- `ARM_CLIENT_ID`
- `ARM_TENANT_ID`
- `ARM_SUBSCRIPTION_ID`
- `AZURE_FEDERATED_TOKEN_FILE`
- `TF_BACKEND_RESOURCE_GROUP`
- `TF_BACKEND_STORAGE_ACCOUNT`
- `TF_BACKEND_CONTAINER`
- `TF_BACKEND_KEY`

The pipeline already passes those backend values into `terraform init`.

## Required Azure RBAC

Grant the Jenkins Azure principal:

- `Reader` on the subscription or target resource group for `terraform plan`
- `Storage Blob Data Contributor` on the Terraform backend storage account

If Jenkins will ever perform `terraform apply`, it also needs:

- `Contributor` on the target resource group

## Backend values

Use the values from the bootstrap stack output:

```bash
cd <repo-root>/terraform/bootstrap
terraform output -raw backend_hcl
```

Map them into Jenkins job configuration or controller-managed environment variables.

## Validation flow

1. Jenkins authenticates to Azure using Workload Identity.
2. `terraform init` uses the Azure Storage backend with OIDC and Azure AD auth.
3. `terraform validate` and `terraform plan` run without storage keys or downloaded tfvars blobs.

## What not to do

- Do not store storage account keys in Key Vault for Terraform backend access.
- Do not upload real `terraform.tfvars` into blob storage for CI.
- Do not commit `backend.hcl`, `.tfstate`, or secret exports to Git.
