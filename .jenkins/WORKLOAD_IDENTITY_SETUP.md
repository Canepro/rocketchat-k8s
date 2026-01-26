# Workload Identity Setup for Jenkins

Jenkins is now configured to use **Azure Workload Identity** with the existing ESO (External Secrets Operator) User-Assigned Managed Identity. This eliminates the need for service principals and provides secure, credentialless authentication to Azure.

## What is Workload Identity?

Workload Identity allows Kubernetes pods to authenticate to Azure services using managed identities **without storing secrets**. The pod's service account is annotated with the managed identity's client ID, and Azure automatically provides tokens.

## Current Configuration

- **Jenkins Service Account**: `jenkins` (in `jenkins` namespace)
- **Managed Identity Client ID**: `fe3d3d95-fb61-4a42-8d82-ec0852486531` (ESO identity)
- **Tenant ID**: `c3d431f1-3e02-4c62-a825-79cd8f9e2053`

## Required Permissions

The ESO identity needs these Azure RBAC roles:

### 1. Key Vault Secrets User (Already Configured ✅)
```bash
# Already granted - verified in previous setup
az role assignment list \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-canepro-aks/providers/Microsoft.KeyVault/vaults/aks-canepro-kv-e8d280" \
  --assignee "fe3d3d95-fb61-4a42-8d82-ec0852486531" \
  --query "[?roleDefinitionName=='Key Vault Secrets User']"
```

### 2. Storage Account Access (Needs to be granted)

The identity needs to read from the Storage Account to download `terraform.tfvars`:

```bash
# Set variables
ESO_CLIENT_ID="fe3d3d95-fb61-4a42-8d82-ec0852486531"
STORAGE_ACCOUNT_RESOURCE_ID="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/tfcaneprostate1"

# Grant "Storage Blob Data Reader" role (read-only access to blobs)
az role assignment create \
  --assignee $ESO_CLIENT_ID \
  --role "Storage Blob Data Reader" \
  --scope $STORAGE_ACCOUNT_RESOURCE_ID

# Verify the assignment
az role assignment list \
  --scope $STORAGE_ACCOUNT_RESOURCE_ID \
  --assignee $ESO_CLIENT_ID \
  --query "[?roleDefinitionName=='Storage Blob Data Reader']"
```

**Alternative**: If you prefer to use Storage Account keys (stored in Key Vault), the identity only needs Key Vault access (already configured). The current Jenkinsfiles support both approaches.

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
