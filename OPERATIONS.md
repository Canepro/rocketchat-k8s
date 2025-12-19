# RocketChat Day-2 Operations Guide

This guide provides instructions for managing and maintaining the RocketChat stack via GitOps.

## 🚀 How to Upgrade
To upgrade RocketChat or any microservice:
1.  Open `manifests/rocketchat-server.yaml`.
2.  Locate the `image: tag` for the component you wish to upgrade (e.g., `7.12.2`).
3.  Change the version to the desired release.
4.  Commit and push to the `master` branch.
5.  ArgoCD will detect the change and perform a rolling update.

## 📈 Scaling Microservices
To adjust the number of replicas for a specific service:
1.  Open `manifests/rocketchat-server.yaml`.
2.  Find the `Deployment` for the service (e.g., `rocketchat-account`).
3.  Modify the `replicas: 1` field.
4.  Commit and push to `master`.

## 🛠️ Troubleshooting
If pods are not running or healthy:
1.  **Check ArgoCD UI**: Look for the "Degraded" status and click on the resource to see the "Events" or "Logs".
2.  **CLI Check**:
    ```bash
    kubectl get pods -n rocketchat
    kubectl describe pod <pod-name> -n rocketchat
    kubectl logs <pod-name> -n rocketchat
    ```
3.  **Disk Pressure**: If pods are "Evicted", check the node disk space:
    ```bash
    df -h
    ```

## 🧹 Maintenance
The `k3s-image-prune` CronJob runs every Sunday at 3:00 AM in the `monitoring` namespace to clear unused container images and prevent disk pressure issues.

