# RocketChat GitOps Repository

This repository contains the declarative GitOps configuration for the entire Rocket.Chat stack, managed by ArgoCD on the OKE Hub.

## 🗺️ Architecture
The Rocket.Chat microservices stack is deployed on a K3s Spoke cluster and managed centrally from an ArgoCD instance using a **Split-App Pattern**:

1.  **Rocket.Chat App (Helm)**: Manages the application stack (monolith + microservices) via the official Helm chart + `values.yaml`.
2.  **Ops App (Kustomize)**: Manages infrastructure glue (storage, monitoring, maintenance jobs) via `ops/`.

- **Diagram**: See [DIAGRAM.md](DIAGRAM.md) for the architecture and data flow.
- **Operations**: See [OPERATIONS.md](OPERATIONS.md) for upgrade and maintenance instructions.

## 🚀 Quick Start
To upgrade the Rocket.Chat version:
1.  Edit `values.yaml`.
2.  Change `image.tag` to the desired version.
3.  Commit and push to `master`.

```bash
git push origin master
```
ArgoCD will automatically detect the changes and perform a rolling update.

## 🗄️ MongoDB (Recommended: external via official MongoDB Operator)

Rocket.Chat has indicated the built-in / bundled MongoDB should not be used going forward (Bitnami images are no longer produced and there are security/maintenance concerns). The recommended direction is to run MongoDB independently using the official MongoDB Kubernetes Operator and point Rocket.Chat at it.

- **Reference instructions (upstream community guide)**: `https://gist.github.com/geekgonecrazy/5fcb04aacadaa310aed0b6cc71f9de74`
- **Operator ArgoCD app (this repo)**: `GrafanaLocal/argocd/applications/aks-rocketchat-mongodb-operator.yaml`
- **MongoDBCommunity example (this repo)**: `ops/manifests/mongodb-community.example.yaml`

This repo configures Rocket.Chat to read its Mongo connection string from `existingMongodbSecret` (key `mongo-uri`) so credentials are not stored in git.

## 🔐 GitOps-first Secrets (Recommended on Azure)

We should avoid manual `kubectl create secret ...` for anything that must persist. For Azure, the recommended model is:

- **External Secrets Operator (ESO)** reconciles `ExternalSecret` manifests from git into Kubernetes Secrets.
- **Azure Key Vault** stores the actual secret values.
- **ArgoCD remains the deploy engine** (GitOps); CI can validate changes, but should not apply to the cluster.

See `OPERATIONS.md` and `MIGRATION_STATUS.md`.

## 📊 Health Dashboard
Monitor the real-time status of your stack here:
[https://argocd.canepro.me](https://argocd.canepro.me)

## 🧹 Maintenance
The workspace includes an automated weekly maintenance job (`k3s-image-prune`) that runs every Sunday at 3:00 AM to prevent disk pressure issues by clearing unused container images.

## 🧪 Tracing Validation (Tempo)
To validate tracing end-to-end (tracegen → OTel Collector → Tempo), see `OPERATIONS.md` → **"Validate Tracing End-to-End (Tracegen → OTel Collector → Tempo)"**.

## 🔧 Troubleshooting

- **DNS & TLS Issues**: See [`TROUBLESHOOTING_DNS_TLS.md`](TROUBLESHOOTING_DNS_TLS.md) for comprehensive guide on:
  - ACME certificate issuance failures
  - Network Security Group configuration
  - ArgoCD and cert-manager conflicts
  - Verification procedures

- **General Operations**: See [`OPERATIONS.md`](OPERATIONS.md) for day-2 operations, upgrades, and common issues.

- **Migration Status**: See [`MIGRATION_STATUS.md`](MIGRATION_STATUS.md) for current migration progress and completed tasks.
