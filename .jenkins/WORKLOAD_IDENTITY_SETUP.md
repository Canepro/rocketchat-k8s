# Workload Identity Setup for Jenkins

Jenkins is configured to use **Azure Workload Identity** with the existing ESO (External Secrets Operator) User-Assigned Managed Identity. This eliminates the need for service principals and provides secure, credentialless authentication to Azure.

## What is Workload Identity?

Workload Identity allows Kubernetes pods to authenticate to Azure services using managed identities **without storing secrets**. The pod's service account is annotated with the managed identity's client ID, and Azure automatically provides tokens.

## Current Configuration

These values are specific to the current personal Azure deployment. If you fork this repo or deploy the same pattern to another environment, replace the IDs and resource names below with values from `terraform output`, Azure Portal, or `az` CLI for that target environment.

- **Jenkins Service Account**: `jenkins` (in `jenkins` namespace)
- **Managed Identity Client ID**: `8035be61-f232-4c44-8ca5-13378b33c2d9` (shared ESO/Jenkins identity)
- **Managed Identity Principal ID**: `63b247e6-f016-47e2-b103-b38ac92ae389`
- **Tenant ID**: `040f4d47-c5be-488d-a48b-4b43fe04cac4`
- **Subscription ID**: `d3b51a0d-cdf1-445e-bac3-28e65892afbc`

## Required Permissions

The shared ESO/Jenkins identity (`aks-canepro-eso-identity`) needs these Azure RBAC roles for Jenkins Terraform validation:

### 1. Key Vault Secrets User (Configured via Terraform)
For External Secrets Operator and Jenkins Terraform validation to read Key Vault secrets during refresh.
```bash
az role assignment list \
  --scope "/subscriptions/d3b51a0d-cdf1-445e-bac3-28e65892afbc/resourceGroups/rg-canepro-aks/providers/Microsoft.KeyVault/vaults/aks-canepro-kv-2e552c" \
  --assignee-object-id "63b247e6-f016-47e2-b103-b38ac92ae389" \
  --output table
```

### 2. Storage Account Access (Configured in backend bootstrap)
For Terraform backend state storage:

| Role | Scope | Purpose |
|------|-------|---------|
| `Storage Blob Data Contributor` | Storage Account | Read/write/lock terraform state files |

```bash
# Verify storage account roles
az role assignment list \
  --scope "/subscriptions/d3b51a0d-cdf1-445e-bac3-28e65892afbc/resourceGroups/rg-canepro-tfstate/providers/Microsoft.Storage/storageAccounts/caneprotfgmhl5a" \
  --assignee-object-id "63b247e6-f016-47e2-b103-b38ac92ae389" \
  --output table
```

### 3. Subscription Access (Configured via Terraform)
For Terraform to read existing Azure resources during plan refresh:

| Role | Scope | Purpose |
|------|-------|---------|
| `Reader` | Subscription | Read all Azure resources for terraform plan |

```bash
# Verify subscription-level roles
az role assignment list \
  --assignee-object-id "63b247e6-f016-47e2-b103-b38ac92ae389" \
  --scope "/subscriptions/d3b51a0d-cdf1-445e-bac3-28e65892afbc" \
  --output table
```

### 4. AKS Cluster Credential Access (Configured via Terraform)
For Terraform to refresh the AKS cluster resource and read user kubeconfig credentials during plan:

| Role | Scope | Purpose |
|------|-------|---------|
| `Azure Kubernetes Service Cluster User Role` | AKS managed cluster | Allow `listClusterUserCredential` during terraform refresh |

```bash
# Verify AKS cluster-user role
az role assignment list \
  --assignee-object-id "63b247e6-f016-47e2-b103-b38ac92ae389" \
  --scope "/subscriptions/d3b51a0d-cdf1-445e-bac3-28e65892afbc/resourceGroups/rg-canepro-aks/providers/Microsoft.ContainerService/managedClusters/aks-canepro" \
  --output table
```

### Full Role Summary

| Role | Scope | Status |
|------|-------|--------|
| Key Vault Secrets User | Key Vault | Managed by Terraform |
| Storage Blob Data Contributor | Backend storage account (`caneprotfgmhl5a`) | Managed by backend bootstrap |
| Reader | Subscription | Managed by Terraform |
| Azure Kubernetes Service Cluster User Role | AKS cluster (`aks-canepro`) | Managed by Terraform |

**Note**: For `terraform apply` (not currently enabled), the identity would need `Contributor` role on the resource group instead of just `Reader`.

## How It Works

1. **Pod starts** with service account `jenkins` (annotated with managed identity client ID)
2. **Azure Workload Identity webhook** (already running in your cluster) injects a token file
3. **Terraform/Azure SDK** in the pod uses the federated token automatically
4. **No secrets needed** - authentication is handled by Azure

## Testing Workload Identity

After granting permissions, test from a Jenkins pod:

```bash
VAULT_NAME="aks-canepro-kv-2e552c"
STORAGE_ACCOUNT="caneprotfgmhl5a"
CONTAINER_NAME="tfstate"
SECRET_NAME="jenkins-github-token"

# Get into a Jenkins agent pod
kubectl exec -it -n jenkins <jenkins-agent-pod> -- bash

# Test Key Vault access
az keyvault secret show \
  --vault-name "${VAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --query value -o tsv

# Test backend access (if Storage Blob Data Contributor is granted)
az storage blob list \
  --account-name "${STORAGE_ACCOUNT}" \
  --container-name "${CONTAINER_NAME}" \
  --auth-mode login \
  --output table
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
- Ensure the identity's principal ID matches: `63b247e6-f016-47e2-b103-b38ac92ae389`
