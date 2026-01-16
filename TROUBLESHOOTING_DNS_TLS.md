# DNS & TLS Troubleshooting Guide - AKS Migration

This document captures the issues, root causes, and solutions encountered during the DNS cutover and TLS certificate provisioning for the AKS migration (January 2026).

## Overview

During the migration from k3s to AKS, we encountered multiple interconnected issues preventing successful TLS certificate issuance via Let's Encrypt. This guide documents the troubleshooting journey and final solutions.

## Timeline of Issues

### Issue 1: Missing Ingress Controller
**Symptom**: No ingress controller deployed on AKS cluster  
**Status**: ✅ Resolved  
**Solution**: Deployed Traefik via ArgoCD GitOps

### Issue 2: DNS Not Pointing to New Cluster
**Symptom**: Domain `k8.canepro.me` still pointing to old k3s cluster IP  
**Status**: ✅ Resolved  
**Solution**: Updated DNS A record to point to new LoadBalancer IP (`85.210.181.37`)

### Issue 3: ACME Challenge Routing Failures (403 Errors)
**Symptom**: Cert-manager challenges returning `403 Forbidden` instead of `200 OK`  
**Status**: ✅ Resolved  
**Root Cause**: ArgoCD's `selfHeal` was reverting cert-manager's in-place ingress modifications  
**Solution**: Added `ignoreDifferences` to ArgoCD Application manifest

### Issue 4: Persistent Timeout Errors from Let's Encrypt
**Symptom**: Certificate orders failing with `Timeout during connect (likely firewall problem)`  
**Status**: ✅ Resolved  
**Root Cause**: Subnet-level NSG blocking inbound traffic on ports 80/443  
**Solution**: Added security rule to subnet NSG via Terraform

---

## Detailed Issue Analysis

### Issue 3: ACME Challenge Routing Failures

#### Problem Description
Cert-manager was creating ACME challenge paths on the RocketChat Ingress, but Traefik logs showed all challenge requests returning `403 Forbidden` and being routed to the RocketChat backend instead of the cert-manager solver pods.

#### Root Cause
We initially used `acme.cert-manager.io/http01-edit-in-place: "true"` annotation, which allows cert-manager to modify the existing Ingress resource in-place by adding a temporary path for the ACME challenge.

However, ArgoCD's `selfHeal: true` policy was detecting these modifications as drift and automatically reverting them, creating a race condition:
1. Cert-manager adds challenge path to Ingress
2. Traefik picks up the change and routes correctly (briefly)
3. ArgoCD detects drift and reverts the Ingress
4. Challenge path disappears
5. Let's Encrypt validation fails

#### Solution 1: ignoreDifferences (Partial Fix)
We added `ignoreDifferences` to the ArgoCD Application manifest to tell ArgoCD to ignore changes to the Ingress paths:

```yaml
# GrafanaLocal/argocd/applications/aks-rocketchat-helm.yaml
spec:
  ignoreDifferences:
    - group: networking.k8s.io
      kind: Ingress
      name: rocketchat-rocketchat
      jsonPointers:
        - /spec/rules/0/http/paths
```

**Result**: This helped, but we still saw intermittent failures.

#### Solution 2: Dedicated Challenge Ingress (Final Fix)
We removed the `http01-edit-in-place` annotation and let cert-manager create a **separate** Ingress resource specifically for challenges:

**File**: `values.yaml`
```yaml
ingress:
  enabled: true
  ingressClassName: traefik
  annotations:
    cert-manager.io/cluster-issuer: production-cert-issuer
    # Removed: acme.cert-manager.io/http01-edit-in-place: "true"
```

**File**: `ops/manifests/clusterissuer.yaml`
```yaml
spec:
  acme:
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
```

**Result**: Cert-manager now creates a separate Ingress named `cm-acme-http-solver-xxxxx` which:
- Is not managed by ArgoCD (no conflict)
- Routes `/.well-known/acme-challenge/*` to cert-manager solver pods
- Is automatically cleaned up after certificate issuance

**Key Learning**: Using dedicated challenge Ingresses avoids GitOps conflicts entirely.

---

### Issue 4: Network Security Group Blocking Traffic

#### Problem Description
Despite successful internal routing (Traefik logs showed `200 OK` responses), Let's Encrypt validation consistently failed with:
```
acme: authorization error for k8.canepro.me: 400 urn:ietf:params:acme:error:connection: 
85.210.181.37: Fetching http://k8.canepro.me/.well-known/acme-challenge/...: 
Timeout during connect (likely firewall problem)
```

External connectivity tests (`curl http://k8.canepro.me` from internet) also timed out.

#### Root Cause Analysis

Azure AKS has **multiple layers** of Network Security Groups:

1. **Node-level NSG** (`aks-agentpool-39103326-nsg`)
   - Attached to individual VM network interfaces
   - ✅ Had rule allowing Internet → LoadBalancer IP on ports 80/443

2. **Subnet-level NSG** (`aks-canepro-nsg`)
   - Attached to the subnet containing the AKS nodes
   - ❌ **Had NO rule allowing inbound traffic from Internet**
   - Default rule: `DenyAllInBound` (Priority 65500)

**Traffic Flow**:
```
Internet → LoadBalancer (85.210.181.37) → Subnet NSG → Node NSG → Pod
```

Traffic was being **dropped at the Subnet NSG** before it could reach the Node NSG, even though the Node NSG had the correct rule.

#### Solution

Added security rule to the subnet NSG via Terraform:

**File**: `terraform/network.tf`
```hcl
resource "azurerm_network_security_group" "aks" {
  name                = "${var.cluster_name}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowHttpHttps"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = var.tags
}
```

**Applied via**:
```bash
cd terraform
terraform plan -out=tfplan
terraform apply tfplan
```

**Result**: 
- ✅ External connectivity restored (`curl http://k8.canepro.me` returns `200 OK`)
- ✅ Let's Encrypt validation succeeded
- ✅ Certificate issued successfully (`READY: True`)

**Key Learning**: In Azure, **subnet-level NSGs are evaluated before node-level NSGs**. Both must allow traffic for it to flow.

---

## Verification Commands

### Check Certificate Status
```bash
kubectl get certificate -n rocketchat
kubectl describe certificate rocketchat-tls -n rocketchat
```

### Check ACME Resources
```bash
kubectl get order,challenge,certificaterequest -n rocketchat
kubectl describe order -n rocketchat
kubectl describe challenge -n rocketchat
```

### Check Traefik Routing
```bash
kubectl logs -n traefik deploy/traefik | grep "well-known"
```

### Test External Connectivity
```bash
# HTTP
curl -I http://k8.canepro.me

# HTTPS
curl -I https://k8.canepro.me

# DNS Resolution
curl -sH "accept: application/dns-json" \
  "https://cloudflare-dns.com/dns-query?name=k8.canepro.me&type=A"
```

### Check NSG Rules (Azure CLI)
```bash
# Subnet NSG
az network nsg rule list \
  --resource-group rg-canepro-aks \
  --nsg-name aks-canepro-nsg \
  --query "[].{Name:name, Priority:priority, Direction:direction, Access:access, Port:destinationPortRanges}" \
  -o table

# Node NSG (in managed resource group)
az network nsg rule list \
  --resource-group MC_rg-canepro-aks_aks-canepro_uksouth \
  --nsg-name aks-agentpool-39103326-nsg \
  --query "[].{Name:name, Priority:priority, Direction:direction, Access:access, Port:destinationPortRanges}" \
  -o table
```

---

## Clean Certificate Re-issuance Procedure

If you need to force a fresh certificate issuance:

```bash
# 1. Delete all ACME resources
kubectl delete certificate rocketchat-tls -n rocketchat
kubectl delete secret rocketchat-tls -n rocketchat
kubectl delete order --all -n rocketchat
kubectl delete challenge --all -n rocketchat
kubectl delete certificaterequest --all -n rocketchat

# 2. Verify clean slate
kubectl get certificate,order,challenge,certificaterequest -n rocketchat

# 3. Watch new issuance (certificate will be auto-created by ingress-shim)
kubectl get certificate -n rocketchat -w
```

The Ingress annotation `cert-manager.io/cluster-issuer: production-cert-issuer` will automatically trigger a new Certificate resource.

---

## Best Practices Learned

### 1. Ingress Controller Deployment
- ✅ Deploy ingress controller **before** attempting certificate issuance
- ✅ Use GitOps (ArgoCD) for consistency
- ✅ Verify LoadBalancer IP assignment before DNS cutover

### 2. Cert-Manager Configuration
- ✅ Prefer **dedicated challenge Ingresses** over `http01-edit-in-place`
- ✅ Avoid GitOps conflicts by not managing challenge resources
- ✅ Use `ingressClassName` in ClusterIssuer to match your ingress controller

### 3. Azure Network Security
- ✅ **Always check subnet-level NSGs** in addition to node-level NSGs
- ✅ Use Terraform to manage NSG rules (Infrastructure as Code)
- ✅ Test external connectivity before certificate issuance
- ✅ Remember: Subnet NSG is evaluated **before** Node NSG

### 4. GitOps Best Practices
- ✅ Use `ignoreDifferences` sparingly (only when necessary)
- ✅ Prefer architectural solutions (separate resources) over ignoring drift
- ✅ Document why `ignoreDifferences` is needed if used

### 5. Troubleshooting Methodology
- ✅ Start with external connectivity tests (`curl` from internet)
- ✅ Check Traefik logs for routing decisions
- ✅ Verify NSG rules at **all layers** (subnet + node)
- ✅ Use `kubectl describe` to see detailed error messages
- ✅ Clean up stale ACME resources before retrying

---

## Related Files

- **Terraform NSG Configuration**: `terraform/network.tf`
- **RocketChat Ingress Config**: `values.yaml` (ingress section)
- **Cert-Manager ClusterIssuer**: `ops/manifests/clusterissuer.yaml`
- **ArgoCD Application**: `GrafanaLocal/argocd/applications/aks-rocketchat-helm.yaml`
- **Traefik Values**: `traefik-values.yaml`

---

## References

- [Cert-Manager HTTP-01 Challenge](https://cert-manager.io/docs/configuration/acme/http01/)
- [Azure NSG Documentation](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [ArgoCD ignoreDifferences](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#ignore-differences)
- [Traefik Ingress Controller](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)

---

## Date
Documented: 2026-01-16  
Migration: k3s → AKS  
Domain: `k8.canepro.me`  
Certificate Issuer: Let's Encrypt (production)
