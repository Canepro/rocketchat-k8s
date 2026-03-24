# AKS Migration Status (Plan Cross‑Check)

## 🎉 MIGRATION COMPLETE (2026-01-20)

> **Git default branch (2026-03-24):** Default branch on GitHub is now **main** (renamed from **master**). ArgoCD apps and Jenkins jobs for this repo track **main**.

The AKS migration has been **successfully completed** and merged to the `main` branch:
- ✅ All infrastructure deployed on AKS
- ✅ DNS cutover complete and stable (4+ days)
- ✅ All ArgoCD applications tracking `main` branch
- ✅ Production traffic running on AKS
- ✅ Monitoring and maintenance automation deployed

This file tracks **where we are vs** the original migration plan (`.cursor/plans/rocketchat_migration_to_azure_aks_-_complete_with_observability_1ffff811.plan.md`).

## Current State (as of 2026‑03‑18)

- **Migration Status**: ✅ **COMPLETE** - Merged to `main` branch, all ArgoCD apps tracking `main`
- **AKS cluster**: running (auto-start/stop configured: 13:30-16:15 Europe/London on weekdays, stays off weekends), Terraform plan clean after azurerm v4 apply.
- **Jenkins CI**: Terraform plan parity clean (no changes detected) after azurerm v4 apply (2026-02-04).
- **Cost Optimization**: Short work-window schedule reduces monthly runtime to ~55 hours/month on the personal PAYG subscription.
- **ArgoCD apps (AKS)** - All tracking `main` branch:
  - `aks-rocketchat-ops`: syncing / infrastructure + observability.
  - `aks-rocketchat-helm`: Rocket.Chat Helm deploy.
  - `aks-rocketchat-mongodb-operator`: MongoDB Community Operator (Helm) deployed.
  - `aks-rocketchat-external-secrets`: ESO Helm chart.
  - `aks-rocketchat-secrets`: ClusterSecretStore + ExternalSecrets.
  - `aks-jenkins`: Jenkins CI/CD deployed and running.
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
- **Secret Protection** (2026-01-25): All Key Vault secret resources use `ignore_changes = [value]` to prevent Terraform from overwriting secrets when `terraform.tfvars` has placeholders

### Key Vault Secrets (managed by Terraform)
- `rocketchat-mongo-uri`
- `rocketchat-mongo-oplog-uri`
- `rocketchat-mongodb-admin-password`
- `rocketchat-mongodb-rocketchat-password`
- `rocketchat-mongodb-metrics-endpoint-password`
- `rocketchat-observability-username`
- `rocketchat-observability-password`
- `jenkins-admin-username` ✅ **(2026-01-19)**
- `jenkins-admin-password` ✅ **(2026-01-19)**
- `jenkins-github-token` ✅ **(2026-01-19)**

## Plan Cross‑Check (High‑Level)

### Phase 0: Document current state
- **Done**: `MIGRATION_STATUS.md`, `OPERATIONS.md`, `terraform/README.md` updated.

### Phase 1–2: Terraform / AKS creation
- **Done**: AKS exists, state in Azure Storage backend.
- **Note (2026-02-04)**: Current plan has 2 in-place changes due to azurerm v4 upgrade (apply pending after merge).

### Phase 3–4: Observability secret + cluster labels
- **Done**: Cluster labels configured, Prometheus Agent + OTel Collector deployed.
- **Still to verify**: metrics/traces flow end-to-end from AKS → hub (Grafana/Mimir + Tempo).

### Phase 5: Dual ArgoCD apps (Helm + Ops)
- **Done**: `aks-rocketchat-helm` and `aks-rocketchat-ops` exist and are syncing.

### Phase 6–7: Storage + initial deploy
- **Done**: storage class aligned; Rocket.Chat + ops resources deployed.

### Phase 8: Observability verification (must do)
- **Setup Complete**: Verification guide and script created (2026-01-16)
  - Guide: `ops/manifests/observability-verification.md`
  - Script: `ops/scripts/verify-observability.sh`
- **Cluster Status Verified** ✅ (2026-01-16):
  - ✅ Prometheus Agent: Running, no remote_write errors
  - ✅ OTel Collector: Running, no export errors
  - ✅ Configuration: Correct cluster labels (`aks-canepro`)
  - ✅ Secrets: observability-credentials exists
- **Grafana Metrics Verification** ✅ (2026-01-16):
  - ✅ Metrics flowing: **6,205 series** visible with `cluster=aks-canepro` label
  - ✅ Remote write working: Cert-manager and other metrics successfully ingested
  - ✅ Prometheus Agent self-metrics scrape job added: Enables `prometheus_remote_storage_*` metrics monitoring
- **Pending**: 
  - Traces with `cluster=aks-canepro` searchable in Grafana Tempo

### Phase 8b: Loki logging (recommended next)
- **Pending deploy**: Promtail DaemonSet ships Kubernetes pod logs to central Loki.
  - Manifests: `ops/manifests/promtail-*.yaml` (added, v3.6.0)
  - Endpoint: `https://observability.canepro.me/loki/api/v1/push` (via `observability-credentials`)
  - **Note**: Promtail will be deprecated in favor of Grafana Alloy after March 2026 (see `VERSIONS.md`)

### Phase 9–11: Data migration + cutover + monitoring
- **DNS Cutover**: ✅ **Complete** (2026-01-16)
  - Domain `k8.canepro.me` pointing to AKS LoadBalancer IP (`85.210.181.37`)
  - Let's Encrypt TLS certificate issued and valid
  - HTTPS accessible and working
- **Pending / not recorded** in repo yet:
  - export/import procedures, validation checklist completion, post-cutover monitoring.

## Completed Tasks (2026-02-04)

- [x] **azurerm v4 upgrade applied** (2026-02-04)
- [x] Terraform plan clean after apply (2026-02-04)

## Completed Tasks (2026-01-20)

- [x] **Automated maintenance jobs deployed** (2026-01-20):
  - `aks-stale-pod-cleanup` CronJob: Weekday cleanup of orphaned pods after cluster restart (`0 14 * * 1-5`, 14:00 Europe/London)
  - Grafana monitoring dashboard imported (`grafana-dashboard-maintenance-jobs.json`)
  - Alert rules created (`grafana-alerts-maintenance-jobs.yaml`)
  - Documentation: `ops/MAINTENANCE_MONITORING.md`
  - **Status**: ✅ Deployed and tested successfully

## Completed Tasks (2026-01-19)

- [x] Terraform plan clean (0 changes) as of 2026-01-19
- [x] ESO + AKV secrets GitOps working
- [x] Legacy Bitnami MongoDB removed from cluster
- [x] Legacy `rocketchat-mongodb.yaml` manifest deleted from repo
- [x] All RocketChat pods healthy
- [x] **Traefik ingress controller deployed** (GitOps via ArgoCD)
- [x] **DNS cutover completed** (`k8.canepro.me` → AKS LoadBalancer)
- [x] **TLS certificate issued** (Let's Encrypt, `READY: True`)
- [x] **Network Security Group configured** (subnet-level HTTP/HTTPS rules via Terraform)
- [x] **Node pool upgraded** (`Standard_B2s` → `Standard_D4as_v5`) - Memory: 90-95% → 9-26%
- [x] **Azure Automation configured** (current schedule: 13:30 start, 16:15 stop Europe/London on weekdays) - updated post-cutover for personal PAYG cost control
- [x] **Jenkins infrastructure ready** (2026-01-19):
  - ArgoCD application manifest created (`aks-jenkins.yaml`)
  - Helm values configured (`jenkins-values.yaml`) - Latest LTS 2.528.3 + JDK 21
  - External Secrets configured (`externalsecret-jenkins.yaml`)
  - Terraform variables added for Jenkins credentials
  - 3 secrets created in Azure Key Vault (admin username/password, GitHub token)
  - Deployment guide created (`JENKINS_DEPLOYMENT.md`)
  - DNS A record configured (`jenkins.canepro.me`)
  - **Status**: Historical pre-cutover note; Jenkins was staged before the old 16:00 Europe/London weekday startup window and is now superseded by the current 13:30 Europe/London schedule.

## Completed Upgrades (2026-01-16)

### Node Size Upgrade ✅ **Complete**
- **Previous**: `Standard_B2s` (2 vCPU, 4GB RAM) - Memory usage: 90-95%
- **Current**: `Standard_D4as_v5` (4 vCPU, 16GB RAM) - Memory usage: 9-26%
- **Upgrade Duration**: 14m19s (rolling update, no downtime)
- **Result**: Memory headroom increased from ~140MB free to ~12GB+ free per node
- **Terraform Config**: Updated with `temporary_name_for_rotation = "tempnodepool"`
- **Status**: ✅ Complete - All pods healthy, cluster stable

## Next Steps (Post-Migration)

1. ✅ **Migration Complete** (2026-01-20):
   - Merged to `main` branch
   - All ArgoCD apps tracking `main`
   - All systems healthy and stable

2. **Ongoing Monitoring** (Current):
   - Monitor cluster stability and performance
   - Review Grafana dashboards regularly
   - Address any user feedback

3. **Future Enhancements**:
   - **Traces verification**: Verify traces flowing to Tempo (metrics already confirmed)
   - **Loki logging**: Deploy Promtail logs to central Loki (optional)
   - **RocketChat upgrade**: Plan upgrade to 8.x.x (requires MongoDB upgrade first)

4. **Old Cluster Cleanup** (After 30 days of stable operation):
   - Currently powered off, VM preserved as backup
   - **Action**: Review and decommission after 2026-02-20

## Cutover to Main Branch ✅ COMPLETE (2026-01-20)

### Completion Summary
- ✅ **DNS cutover complete**: `k8.canepro.me` → AKS LoadBalancer (`85.210.181.37`)
- ✅ **TLS certificate issued**: Let's Encrypt certificate valid and working
- ✅ **All ArgoCD apps syncing**: All AKS applications now tracking `main` branch
- ✅ **Production traffic**: All users accessing AKS cluster
- ✅ **Branch merge complete**: `aks-migration` merged to `main` (2026-01-20)
- ✅ **ArgoCD apps updated**: All apps switched from `aks-migration` → `main` (2026-01-20)
- ✅ **Old cluster apps removed**: Legacy `k8-canepro-rocketchat` apps deleted from ArgoCD

### When to Merge to Main

**Recommended: After 7-14 days of stable operation on AKS**

**Rationale:**
- Stability period to catch any hidden issues
- User validation with real-world usage
- Easier rollback via DNS if needed (vs. undoing merge)
- Time to verify observability metrics/traces

### Minimum Requirements Before Merge ✅ ALL COMPLETE

- [x] **DNS cutover stable** (✅ Done - 2026-01-16) - Stable for 4+ days
- [x] **TLS certificate valid** (✅ Done - 2026-01-16)
- [x] **All pods healthy** for at least 48 hours (✅ 4+ days running)
- [x] **Automated maintenance** (✅ Done - 2026-01-20) - Pod cleanup + monitoring
- [x] **No critical errors** in RocketChat logs (✅ Verified - 2026-01-20)
- [x] **User acceptance**: No major user-reported issues (✅ Verified - 2026-01-20)
- [x] **Observability verified**: Metrics flowing to Grafana (✅ 6,205 series, traces pending)
- [x] **Data integrity confirmed**: All data accessible, no corruption (✅ Verified - 2026-01-20)

### Merge Process ✅ COMPLETE (2026-01-20)

1. ✅ **Merge `aks-migration` → `main`** (Complete)
   - Fast-forward merge completed
   - 68 files changed (+7,628 insertions, -1,064 deletions)
   - Commit: `41ef826` → `25e3603`

2. ✅ **Update ArgoCD Applications** (Complete)
   - Updated `targetRevision: aks-migration` to track the post-migration default branch in all 5 apps (was **master**, renamed **main** on 2026-03-24):
     - ✅ `GrafanaLocal/argocd/applications/aks-rocketchat-helm.yaml`
     - ✅ `GrafanaLocal/argocd/applications/aks-rocketchat-ops.yaml`
     - ✅ `GrafanaLocal/argocd/applications/aks-rocketchat-secrets.yaml`
     - ✅ `GrafanaLocal/argocd/applications/aks-traefik.yaml`
     - ✅ `GrafanaLocal/argocd/applications/aks-jenkins.yaml`
   - Committed and pushed (commit `25e3603`)
   - Applied to cluster via `kubectl apply`

3. ✅ **Update Documentation** (Complete)
   - Updated `README.md`, `OPERATIONS.md`, `MIGRATION_STATUS.md`
   - All references to `aks-migration` branch replaced with `main`

4. ✅ **Verify ArgoCD Sync** (Complete)
   - All apps showing `Synced & Healthy`
   - All apps tracking `main` branch
   - All pods running successfully

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

### Timeline ✅ COMPLETE

```
Day 0:  DNS cutover (✅ Done - 2026-01-16)
Day 1-4: Monitor stability, verify all systems (✅ Complete)
Day 4:  Merge to default branch (**main**), update ArgoCD apps (✅ Done - 2026-01-20)
Day 30+: Detach old cluster (Scheduled)
```

**Actual Timeline:**
- **2026-01-16**: DNS cutover to AKS
- **2026-01-16 to 2026-01-20**: Stability monitoring (4 days)
- **2026-01-20**: Merged to `main`, updated ArgoCD apps
- **Result**: Migration completed in 4 days (faster than planned 14 days due to excellent stability)

## Troubleshooting Documentation

For issues encountered during DNS/TLS setup, see:
- **`TROUBLESHOOTING_DNS_TLS.md`**: Comprehensive guide covering:
  - ACME challenge routing failures (ArgoCD conflicts)
  - Network Security Group configuration issues
  - Verification commands and clean re-issuance procedures
  - Best practices learned

For Jenkins deployment and troubleshooting, see:
- **`JENKINS_DEPLOYMENT.md`**: Complete Jenkins deployment guide covering:
  - Quick deployment steps (5 steps)
  - Configuration and customization
  - Creating CI jobs (Terraform, Helm, OPA/Conftest examples)
  - Security best practices and hardening
  - Monitoring with Prometheus
  - Troubleshooting common issues
  - Upgrade procedures
