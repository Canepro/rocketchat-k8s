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

## 📊 Health Dashboard
Monitor the real-time status of your stack here:
[https://argocd.canepro.me](https://argocd.canepro.me)

## 🧹 Maintenance
The workspace includes an automated weekly maintenance job (`k3s-image-prune`) that runs every Sunday at 3:00 AM to prevent disk pressure issues by clearing unused container images.

## 🧪 Tracing Validation (Tempo)
To validate tracing end-to-end (tracegen → OTel Collector → Tempo), see `OPERATIONS.md` → **“Validate Tracing End-to-End (Tracegen → OTel Collector → Tempo)”**.