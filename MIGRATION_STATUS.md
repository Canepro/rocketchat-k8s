# AKS Migration Status (Plan Cross‑Check)

This file tracks **where we are vs** `.cursor/plans/rocketchat_migration_to_azure_aks_-_complete_with_observability_1ffff811.plan.md`.

## Current State (as of 2026‑01‑16)

- **AKS cluster**: running, Terraform plan clean (0 changes).
- **ArgoCD apps (AKS)**:
  - `aks-rocketchat-ops`: syncing / infrastructure + observability.
  - `aks-rocketchat-helm`: Rocket.Chat Helm deploy.
  - `aks-rocketchat-mongodb-operator`: MongoDB Community Operator (Helm) deployed.
  - `aks-rocketchat-external-secrets`: ESO Helm chart.
  - `aks-rocketchat-secrets`: ClusterSecretStore + ExternalSecrets.
- **MongoDB**:
  - **Operator-managed MongoDB** is **Running** (`mongodb-0`, 2/2 containers).
  - **Legacy Bitnami MongoDB** has been **removed** (StatefulSet, services, configmaps, secrets deleted 2026-01-16).
- **Rocket.Chat**:
  - `rocketchat-rocketchat` is **Running**.
  - All microservices are **Running** (`account`, `authorization`, `ddp-streamer`, `presence`).
- **Secrets**: Managed via **External Secrets Operator + Azure Key Vault** (GitOps-first).

## GitOps Integrity

**Secrets are now GitOps-managed** via External Secrets Operator + Azure Key Vault:
- `ClusterSecretStore` authenticates to AKV using Azure Workload Identity
- `ExternalSecret` resources define which secrets to sync
- Secret values stored in Azure Key Vault (never in git)
- Terraform provisions the Key Vault infrastructure

### Key Vault Secrets (managed by Terraform)
- `rocketchat-mongo-uri`
- `rocketchat-mongo-oplog-uri`
- `rocketchat-mongodb-admin-password`
- `rocketchat-mongodb-rocketchat-password`
- `rocketchat-mongodb-metrics-endpoint-password`

## Plan Cross‑Check (High‑Level)

### Phase 0: Document current state
- **Done**: `MIGRATION_STATUS.md`, `OPERATIONS.md`, `terraform/README.md` updated.

### Phase 1–2: Terraform / AKS creation
- **Done**: AKS exists, Terraform plan clean (0 changes), state in Azure Storage backend.

### Phase 3–4: Observability secret + cluster labels
- **Done**: Cluster labels configured, Prometheus Agent + OTel Collector deployed.
- **Still to verify**: metrics/traces flow end-to-end from AKS → hub (Grafana/Mimir + Tempo).

### Phase 5: Dual ArgoCD apps (Helm + Ops)
- **Done**: `aks-rocketchat-helm` and `aks-rocketchat-ops` exist and are syncing.

### Phase 6–7: Storage + initial deploy
- **Done**: storage class aligned; Rocket.Chat + ops resources deployed.

### Phase 8: Observability verification (must do)
- **Pending**: confirm:
  - Prometheus Agent remote_write success and series visible with the expected `cluster=...` label.
  - OTel Collector exporting traces; traces searchable with expected cluster attribute.

### Phase 9–11: Data migration + cutover + monitoring
- **DNS Cutover**: ✅ **Complete** (2026-01-16)
  - Domain `k8.canepro.me` pointing to AKS LoadBalancer IP (`85.210.181.37`)
  - Let's Encrypt TLS certificate issued and valid
  - HTTPS accessible and working
- **Pending / not recorded** in repo yet:
  - export/import procedures, validation checklist completion, post-cutover monitoring.

## Completed Tasks (2026-01-16)

- [x] Terraform plan clean (0 changes)
- [x] ESO + AKV secrets GitOps working
- [x] Legacy Bitnami MongoDB removed from cluster
- [x] Legacy `rocketchat-mongodb.yaml` manifest deleted from repo
- [x] All RocketChat pods healthy
- [x] **Traefik ingress controller deployed** (GitOps via ArgoCD)
- [x] **DNS cutover completed** (`k8.canepro.me` → AKS LoadBalancer)
- [x] **TLS certificate issued** (Let's Encrypt, `READY: True`)
- [x] **Network Security Group configured** (subnet-level HTTP/HTTPS rules via Terraform)
- [x] **Node pool upgraded** (`Standard_B2s` → `Standard_D4as_v5`) - Memory: 90-95% → 9-26%
- [x] **Azure Automation configured** (scheduled start/stop: 8:30 AM start, 11:00 PM stop on weekdays)

## Completed Upgrades (2026-01-16)

### Node Size Upgrade ✅ **Complete**
- **Previous**: `Standard_B2s` (2 vCPU, 4GB RAM) - Memory usage: 90-95%
- **Current**: `Standard_D4as_v5` (4 vCPU, 16GB RAM) - Memory usage: 9-26%
- **Upgrade Duration**: 14m19s (rolling update, no downtime)
- **Result**: Memory headroom increased from ~140MB free to ~12GB+ free per node
- **Terraform Config**: Updated with `temporary_name_for_rotation = "tempnodepool"`
- **Status**: ✅ Complete - All pods healthy, cluster stable

## Next Steps (Recommended Order)

1. **Observability verification**: run the plan's metrics + traces checks and record results.
2. **Loki logging setup**: Deploy Loki/Promtail to send logs to OKE hub (now have headroom).
3. **Jenkins CI setup**: PR validation jobs (lint, policy checks, terraform plan) - headroom available.
4. **Continue monitoring**: Verify stability for 7-14 days before merging to `main`.

## Cutover to Main Branch

### Current State
- ✅ **DNS cutover complete**: `k8.canepro.me` → AKS LoadBalancer (`85.210.181.37`)
- ✅ **TLS certificate issued**: Let's Encrypt certificate valid and working
- ✅ **All ArgoCD apps syncing**: All AKS applications pointing to `aks-migration` branch
- ✅ **Production traffic**: All users accessing AKS cluster
- ⚠️ **ArgoCD apps still on `aks-migration` branch**: Need to switch to `main`

### When to Merge to Main

**Recommended: After 7-14 days of stable operation on AKS**

**Rationale:**
- Stability period to catch any hidden issues
- User validation with real-world usage
- Easier rollback via DNS if needed (vs. undoing merge)
- Time to verify observability metrics/traces

### Minimum Requirements Before Merge

- [x] **DNS cutover stable** (✅ Done - 2026-01-16)
- [x] **TLS certificate valid** (✅ Done - 2026-01-16)
- [ ] **All pods healthy** for at least 48 hours
- [ ] **No critical errors** in RocketChat logs
- [ ] **User acceptance**: No major user-reported issues
- [ ] **Observability verified**: Metrics/traces flowing to Grafana (optional but recommended)
- [ ] **Data integrity confirmed**: All data accessible, no corruption

### Merge Process

1. **Merge `aks-migration` → `main`**
   - Create PR or direct merge
   - Review changes
   - Merge and push

2. **Update ArgoCD Applications** (after merge)
   - Update `targetRevision: aks-migration` → `targetRevision: main` in:
     - `GrafanaLocal/argocd/applications/aks-rocketchat-helm.yaml`
     - `GrafanaLocal/argocd/applications/aks-rocketchat-ops.yaml`
     - `GrafanaLocal/argocd/applications/aks-rocketchat-secrets.yaml`
     - `GrafanaLocal/argocd/applications/aks-traefik.yaml`
   - Commit and push (ArgoCD will auto-sync)

3. **Update Documentation**
   - `README.md`: Change "K3s Spoke cluster" → "AKS cluster"
   - `DIAGRAM.md`: Update architecture diagram if needed
   - `OPERATIONS.md`: Update any k3s-specific references

4. **Verify ArgoCD Sync**
   ```bash
   argocd app list
   kubectl get pods -n rocketchat
   ```

### Detaching Old Cluster

**Recommended: After 30 days of stable operation on AKS**

**Steps:**
1. Identify old cluster ArgoCD applications: `argocd app list`
2. Delete old applications: `argocd app delete <old-app-name>`
3. Remove old cluster: `argocd cluster rm <old-cluster-name>`
4. Clean up old cluster resources (if no longer needed)
5. Update documentation to remove old cluster references

### Rollback Plan

**Quick Rollback (ArgoCD apps):**
- Revert ArgoCD applications to `aks-migration` branch
- Or revert git merge: `git revert <merge-commit-sha>`

**Emergency Rollback (DNS):**
- Update DNS A record back to old cluster IP
- Wait for DNS propagation
- Investigate and fix issues on AKS

### Timeline

```
Day 0:  DNS cutover (✅ Done - 2026-01-16)
Day 1-7: Monitor stability, verify all systems
Day 7-14: Continue monitoring, verify observability
Day 14+: Merge to main, update ArgoCD apps
Day 30+: Detach old cluster (if stable)
```

## Troubleshooting Documentation

For issues encountered during DNS/TLS setup, see:
- **`TROUBLESHOOTING_DNS_TLS.md`**: Comprehensive guide covering:
  - ACME challenge routing failures (ArgoCD conflicts)
  - Network Security Group configuration issues
  - Verification commands and clean re-issuance procedures
  - Best practices learned

## When to Introduce Jenkins (Guidance)

Introduce Jenkins **after**:
- The two ArgoCD apps are stable and
- Secrets are managed via the chosen GitOps mechanism,

so Jenkins can be used as **CI only** (PR validation + policy checks), not as a deploy tool.

### Azure restriction (from the migration plan)

- **Terraform applies are executed only from Azure Portal / Cloud Shell on your work machine** (environment restriction).
- This means Jenkins should **not** run `terraform apply` in this setup.

Recommended Jenkins jobs:
- `helm template` + `kubeconform` (or `kubeval`) against rendered manifests
- YAML linting (`yamllint`)
- policy checks (OPA/Conftest) for forbidden patterns (e.g., raw Secrets in git)
- optional: `argocd app diff` in "read-only" mode for preview
- optional: Terraform checks (`terraform fmt -check`, `terraform validate`, `terraform plan`) as PR gates (no apply)

Jenkins should **never** run `kubectl apply` to the cluster in normal operation; ArgoCD remains the deploy engine.
