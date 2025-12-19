# ArgoCD Managed RocketChat Workspace

This repository contains the declarative GitOps configuration for the entire Rocket.Chat stack, managed by ArgoCD on the OKE Hub.

## 🗺️ Architecture
The Rocket.Chat microservices stack is deployed on a K3s Spoke cluster and managed centrally from an ArgoCD instance.

- **Diagram**: See [DIAGRAM.md](DIAGRAM.md) for the architecture and data flow.
- **Operations**: See [OPERATIONS.md](OPERATIONS.md) for upgrade and maintenance instructions.

## 🚀 Quick Start
To update the cluster state, simply commit and push your changes to the `master` branch:
```bash
git push origin master
```
ArgoCD will automatically detect the changes and synchronize the cluster.

## 📊 Health Dashboard
Monitor the real-time status of your stack here:
[https://argocd.canepro.me](https://argocd.canepro.me)

## 🧹 Maintenance
The workspace includes an automated weekly maintenance job (`k3s-image-prune`) that runs every Sunday at 3:00 AM to prevent disk pressure issues by clearing unused container images.
