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

## Next Steps (Recommended Order)

1. **Observability verification**: run the plan's metrics + traces checks and record results.
2. **Jenkins CI setup**: PR validation jobs (lint, policy checks, terraform plan).

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
