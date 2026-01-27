# Azure Storage Setup for Terraform Validation

Quick reference for configuring Jenkins to download `terraform.tfvars` from Azure Storage using Key Vault.

## Infrastructure Details

- **Key Vault**: `aks-canepro-kv-e8d280`
- **Storage Account**: `tfcaneprostate1` (in `rg-terraform-state`)
- **Container**: `tfstate`
- **Tenant ID**: `c3d431f1-3e02-4c62-a825-79cd8f9e2053`
- **ESO Identity Client ID**: `fe3d3d95-fb61-4a42-8d82-ec0852486531` (has Key Vault access)

## Quick Setup Steps (Azure Cloud Shell)

### 1. Get Storage Account Key

```bash
STORAGE_ACCOUNT_NAME="tfcaneprostate1"
RESOURCE_GROUP="rg-terraform-state"

STORAGE_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query '[0].value' -o tsv)
```

### 2. Store in Key Vault

```bash
KEY_VAULT_NAME="aks-canepro-kv-e8d280"
SECRET_NAME="storage-account-key"
STORAGE_KEY="<paste-key-from-step-1>"

az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name $SECRET_NAME \
  --value "$STORAGE_KEY"

# Verify
az keyvault secret show \
  --vault-name $KEY_VAULT_NAME \
  --name $SECRET_NAME \
  --query value -o tsv
```

### 3. Verify ESO Identity Has Access (Should Already Work)

```bash
ESO_CLIENT_ID="fe3d3d95-fb61-4a42-8d82-ec0852486531"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
KEY_VAULT_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-canepro-aks/providers/Microsoft.KeyVault/vaults/aks-canepro-kv-e8d280"

# Check access
az role assignment list \
  --scope $KEY_VAULT_RESOURCE_ID \
  --assignee $ESO_CLIENT_ID \
  --query "[?roleDefinitionName=='Key Vault Secrets User']" -o table
```

If it shows a role assignment, you're good! If not, grant access:

```bash
az role assignment create \
  --assignee $ESO_CLIENT_ID \
  --role "Key Vault Secrets User" \
  --scope $KEY_VAULT_RESOURCE_ID
```

## Jenkins Configuration

**✅ Already Configured!** Environment variables are set in the Jenkinsfile itself. No action needed.

The Jenkinsfile includes:

- `AZURE_KEY_VAULT_NAME=aks-canepro-kv-e8d280`
- `AZURE_STORAGE_ACCOUNT_NAME=tfcaneprostate1`
- `AZURE_STORAGE_CONTAINER_NAME=tfstate`
- `AZURE_CLIENT_ID=fe3d3d95-fb61-4a42-8d82-ec0852486531`
- `AZURE_TENANT_ID=c3d431f1-3e02-4c62-a825-79cd8f9e2053`

**Security Note**: For public repos, consider using Jenkins credentials (see `terraform-validation.Jenkinsfile.secure` in GrafanaLocal).

## Status

✅ **Setup Complete!**

- Storage Account key stored in Key Vault
- `terraform.tfvars` uploaded to Azure Storage
- ESO identity has Key Vault access
- Environment variables configured in Jenkinsfile

## Test

Trigger a Jenkins build and check console output for:

- ✅ "Retrieving Storage Account key from Key Vault"
- ✅ "Successfully downloaded terraform.tfvars from Azure Storage"
- ✅ Terraform plan should run successfully

## Troubleshooting

**Authentication fails?**

```bash
# Verify ESO identity can access Key Vault
az keyvault secret show \
  --vault-name aks-canepro-kv-e8d280 \
  --name storage-account-key \
  --query value -o tsv
```

**Blob not found?**

```bash
# Verify terraform.tfvars exists
az storage blob list \
  --account-name tfcaneprostate1 \
  --account-key $STORAGE_KEY \
  --container-name tfstate \
  --query "[?name=='terraform.tfvars']" -o table
```
