# Terraform Backend Bootstrap

This stack creates the Azure Storage backend for the main AKS Terraform state.

It is intentionally separate so the main stack can use remote state without a chicken-and-egg problem.

## What it creates

- Resource group for Terraform state
- Storage account with:
  - `Standard_LRS`
  - HTTPS-only
  - TLS 1.2 minimum
  - blob versioning enabled
  - soft delete enabled
  - OAuth preferred for data access
- Private blob container for state
- `Storage Blob Data Contributor` on the storage account for the currently authenticated Azure principal
- Optional `Storage Blob Data Contributor` assignments for additional principals such as Jenkins Workload Identity

## Usage

```bash
cd <repo-root>/terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw backend_hcl > ../backend.hcl
```

If Jenkins CI or another workload identity also needs backend access, pass the principal IDs during bootstrap:

```bash
terraform plan -out=tfplan \
  -var='additional_blob_data_contributor_principal_ids=["REPLACE_WITH_PRINCIPAL_ID"]'
```

## Compatibility note

The storage account keeps shared access keys enabled because the current AzureRM provider still uses key-based calls in some storage-account create/read paths. Backend authentication should still use Azure AD or OIDC from `backend.hcl`.

Then initialize the main stack:

```bash
cd <repo-root>/terraform
terraform init -reconfigure -backend-config=backend.hcl -migrate-state
```
