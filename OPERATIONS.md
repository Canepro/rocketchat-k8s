# RocketChat Day-2 Operations Guide

This guide provides instructions for managing and maintaining the RocketChat stack via GitOps (ArgoCD + Helm).

## 🚀 How to Upgrade
To upgrade RocketChat (monolith and microservices):
1.  Open `values.yaml` in the root of this repo.
2.  Locate the `image.tag` field (e.g., `7.12.2`).
3.  Change the version to the desired release (e.g., `7.13.2`).
4.  Commit and push to the `master` branch.
5.  ArgoCD will detect the change and perform a rolling update of all components.

## 📈 Scaling Microservices
To adjust the number of replicas for a specific service:
1.  Open `values.yaml`.
2.  Find the `microservices` block.
3.  Modify the `replicas` field for the desired service (e.g., `account`, `presence`, `ddpStreamer`).
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
3.  **Disk Pressure**: If pods are "Evicted" or stuck in `ImagePullBackOff`, check disk space:
    ```bash
    df -h
    ```

## 🧹 Maintenance
The `k3s-image-prune` CronJob runs every Sunday at 3:00 AM in the `monitoring` namespace to clear unused container images and prevent disk pressure issues.

**Manual Run (e.g., if disk is full):**
If the scheduled run was missed or you need space immediately, create a manual job from the cron template:
```bash
kubectl -n monitoring create job --from=cronjob/k3s-image-prune manual-prune-$(date +%s)
```
**Verify it ran:**
```bash
kubectl -n monitoring get jobs
kubectl -n monitoring logs job/manual-prune-<timestamp>
```

## ⚠️ Known Quirks
- **PV Naming**: The PVC `mongo-pvc` is currently bound to a PV named `prometheus-pv`. This is a legacy naming mismatch (Retain policy). Do not rename/delete without a migration plan.
- **Secrets**: `rocketchat-rocketchat` secret is managed by Helm but populated via `values.yaml` (externalMongodbUrl) to preserve legacy passwords. Do not delete it manually.
