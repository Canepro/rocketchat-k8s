# Workload Identity Setup for Jenkins

Jenkins is now configured to use **Azure Workload Identity** with the existing ESO (External Secrets Operator) User-Assigned Managed Identity. This eliminates the need for service principals and provides secure, credentialless authentication to Azure.

## What is Workload Identity?

Workload Identity allows Kubernetes pods to authenticate to Azure services using managed identities **without storing secrets**. The pod's service account is annotated with the managed identity's client ID, and Azure automatically provides tokens.

## Current Configuration

- **Jenkins Service Account**: `jenkins` (in `jenkins` namespace)
- **Managed Identity Client ID**: `fe3d3d95-fb61-4a42-8d82-ec0852486531` (ESO identity)
- **Tenant ID**: `c3d431f1-3e02-4c62-a825-79cd8f9e2053`

## Required Permissions

The ESO identity (`aks-canepro-eso-identity`) needs these Azure RBAC roles for Jenkins terraform validation:

### 1. Key Vault Secrets User (Configured ✅)
For External Secrets Operator to read secrets from Key Vault.
```bash
az role assignment list \
  --scope "/subscriptions/1c6e2ceb-7310-4193-ab4d-95120348b934/resourceGroups/rg-canepro-aks/providers/Microsoft.KeyVault/vaults/aks-canepro-kv-e8d280" \
  --assignee "18a1bdaf-a0f4-45fb-99c7-4f98e659f385" \
  --output table
```

### 2. Storage Account Access (Configured ✅)
For Terraform backend state storage:

| Role | Scope | Purpose |
|------|-------|---------|
| `Reader` | Storage Account | Read storage account properties for terraform init |
| `Storage Blob Data Contributor` | Storage Account | Read/write/lock terraform state files |

```bash
# Verify storage account roles
az role assignment list \
  --scope "/subscriptions/1c6e2ceb-7310-4193-ab4d-95120348b934/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/tfcaneprostate1" \
  --assignee "18a1bdaf-a0f4-45fb-99c7-4f98e659f385" \
  --output table
```

### 3. Subscription/Resource Group Access (Configured ✅)
For Terraform to read existing Azure resources during plan:

| Role | Scope | Purpose |
|------|-------|---------|
| `Reader` | Subscription | Read all Azure resources for terraform plan |
| `Azure Kubernetes Service Cluster User Role` | AKS Cluster | List AKS cluster credentials |

```bash
# Verify subscription-level roles
az role assignment list \
  --assignee "18a1bdaf-a0f4-45fb-99c7-4f98e659f385" \
  --all \
  --output table
```

### Full Role Summary

| Role | Scope | Status |
|------|-------|--------|
| Key Vault Secrets User | Key Vault | ✅ Configured |
| Reader | Storage Account (tfcaneprostate1) | ✅ Configured |
| Storage Blob Data Contributor | Storage Account (tfcaneprostate1) | ✅ Configured |
| Reader | Subscription | ✅ Configured |
| Azure Kubernetes Service Cluster User Role | AKS Cluster | ✅ Configured |

**Note**: For `terraform apply` (not currently enabled), the identity would need `Contributor` role on the resource group instead of just `Reader`.

## How It Works

1. **Pod starts** with service account `jenkins` (annotated with managed identity client ID)
2. **Azure Workload Identity webhook** (already running in your cluster) injects a token file
3. **Azure CLI** in the pod uses `az login --federated-token` automatically
4. **No secrets needed** - authentication is handled by Azure

## Testing Workload Identity

After granting permissions, test from a Jenkins pod:

```bash
# Get into a Jenkins agent pod
kubectl exec -it -n jenkins <jenkins-agent-pod> -- bash

# Authenticate using Workload Identity (automatic if configured)
az login --identity

# Test Key Vault access
az keyvault secret show \
  --vault-name aks-canepro-kv-e8d280 \
  --name storage-account-key \
  --query value -o tsv

# Test Storage Account access (if Storage Blob Data Reader role granted)
az storage blob download \
  --account-name tfcaneprostate1 \
  --container-name tfstate \
  --name terraform.tfvars \
  --file /tmp/test.tfvars
```

## Benefits

✅ **No service principals** - Uses existing managed identity  
✅ **No secrets to manage** - No client secrets or certificates  
✅ **Automatic token rotation** - Azure handles token refresh  
✅ **Audit trail** - All access is logged with the managed identity  
✅ **Simplified CI/CD** - Jenkinsfiles can use `az login --identity` directly

## Troubleshooting

### "Managed Identity authentication failed"

1. **Verify service account annotation**:
   ```bash
   kubectl get serviceaccount jenkins -n jenkins -o yaml | grep azure.workload.identity
   ```

2. **Check Workload Identity webhook is running**:
   ```bash
   kubectl get pods -n kube-system | grep azure-wi-webhook
   ```

3. **Verify identity has correct permissions** (see commands above)

4. **Check pod logs** for authentication errors:
   ```bash
   kubectl logs -n jenkins <jenkins-pod> | grep -i azure
   ```

### "Access denied" when accessing Key Vault or Storage

- Verify the role assignments were created successfully
- Check the scope is correct (resource group or specific resource)
- Ensure the identity's principal ID matches: `18a1bdaf-a0f4-45fb-99c7-4f98e659f385`
