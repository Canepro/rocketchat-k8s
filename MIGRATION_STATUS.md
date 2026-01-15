# AKS Migration Status (Plan Cross‑Check)

This file tracks **where we are vs** `.cursor/plans/rocketchat_migration_to_azure_aks_-_complete_with_observability_1ffff811.plan.md`.

## Current State (as of 2026‑01‑15)

- **AKS cluster**: running.
- **ArgoCD apps (AKS)**:
  - `aks-rocketchat-ops`: syncing / infrastructure + observability.
  - `aks-rocketchat-helm`: Rocket.Chat Helm deploy.
  - `aks-rocketchat-mongodb-operator`: MongoDB Community Operator (Helm) deployed.
- **MongoDB**:
  - **Operator-managed MongoDB** is **Running** (`mongodb-0`).
  - **Legacy Bitnami MongoDB** pod `rocketchat-mongodb-0` still exists and is **CrashLoopBackOff** (to be pruned/removed once cutover is confirmed).
- **Rocket.Chat**:
  - `rocketchat-rocketchat` is **Running**.
  - Most microservices are **Running**; some may still be stabilizing (e.g. `ddp-streamer` previously crash-looped).

## GitOps Integrity (Important)

We currently have **configuration drift** from “pure GitOps” because several **Secrets were created/modified manually** using `kubectl create secret` / `kubectl apply`.

### Manual (non-GitOps) changes performed

- `rocketchat-mongodb-external` (required keys: `mongo-uri`, **`mongo-oplog-uri`**)
- MongoDB operator password secrets:
  - `mongodb-admin-password`
  - `mongodb-rocketchat-password`
  - `metrics-endpoint-password`

**Action required**: migrate these Secrets to a GitOps-managed secret mechanism (recommended: External Secrets Operator + Azure Key Vault).

## Plan Cross‑Check (High‑Level)

### Phase 0: Document current state

- **Partially complete**:
  - We updated `README.md` / `OPERATIONS.md`, but they need a “single source of truth” recap (this file) and a clear statement of GitOps gaps.

### Phase 1–2: Terraform / AKS creation

- **Done** (AKS exists).
- **Follow‑up**: ensure Terraform state and runbooks are committed/consistent with current cluster.

### Phase 3–4: Observability secret + cluster labels

- **Cluster label updates**: appear to be implemented earlier in the branch history.
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

- **Pending / not recorded** in repo yet:
  - export/import procedures, validation checklist completion, DNS cutover, post-cutover monitoring.

## Next Steps (Recommended Order)

1. **Secrets GitOps**: pick a mechanism and implement it (recommendation in `OPERATIONS.md`).
2. **Observability verification**: run the plan’s metrics + traces checks and record results.
3. **Stabilize microservices**: address any remaining crash loops (start with `rocketchat-ddp-streamer` if still failing).
4. **Remove legacy Bitnami MongoDB**: ensure `ops/kustomization.yaml` no longer deploys it; prune old resources safely once operator Mongo is confirmed.
5. **Cutover checklist**: formalize validation + DNS cutover steps and capture “go/no-go” gates.

## When to Introduce Jenkins (Guidance)

Introduce Jenkins **after**:
- The two ArgoCD apps are stable and
- Secrets are managed via the chosen GitOps mechanism,

so Jenkins can be used as **CI only** (PR validation + policy checks), not as a deploy tool.

### Azure restriction (from the migration plan)

- **Terraform applies are executed only from Azure Portal / Cloud Shell on your work machine** (environment restriction).
- This means Jenkins should **not** be responsible for provisioning AKS via Terraform in this setup.

Recommended Jenkins jobs:
- `helm template` + `kubeconform` (or `kubeval`) against rendered manifests
- YAML linting (`yamllint`)
- policy checks (OPA/Conftest) for forbidden patterns (e.g., raw Secrets in git)
- optional: `argocd app diff` in “read-only” mode for preview

Jenkins should **never** run `kubectl apply` to the cluster in normal operation; ArgoCD remains the deploy engine.

