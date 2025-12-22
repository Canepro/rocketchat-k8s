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

### Incident Recovery: MongoDB Stuck (Missing ConfigMap)
**Symptom**: `rocketchat-mongodb-0` pod stuck in `ContainerCreating` or `RunContainerError`.
**Error**: `kubectl describe pod` shows:
```
Warning  FailedMount  ...  MountVolume.SetUp failed for volume "custom-init-scripts" : configmap "rocketchat-mongodb-fix-clustermonitor-role-configmap" not found
```

**Cause**:
The `rocketchat-mongodb` StatefulSet mounts a specific ConfigMap (`rocketchat-mongodb-fix-clustermonitor-role-configmap`) to `/docker-entrypoint-initdb.d`. This ConfigMap was accidentally deleted during a manifest cleanup/refactor (Dec 2025). Without it, the pod cannot mount the volume and fails to start.

**Purpose of `rocketchat-mongodb-fix-clustermonitor-role-configmap`**:
This ConfigMap contains a script (`user_set_role_clusterMonitor.sh`) that runs during MongoDB startup. It explicitly grants the **`clusterMonitor` role** to the `rocketchat` database user on the `admin` database.
- **Why?** The MongoDB Exporter sidecar (and potentially other monitoring tools) needs this permission to query the MongoDB Replica Set status (`replSetGetStatus`). Without it, metrics collection may fail or report errors.

**Resolution Steps**:
1.  Verify the ConfigMap is missing:
    ```bash
    kubectl get configmap rocketchat-mongodb-fix-clustermonitor-role-configmap -n rocketchat
    ```
2.  Restore the definition in `ops/manifests/rocketchat-mongodb.yaml`.
3.  Commit and push to trigger ArgoCD sync (or `kubectl apply -f ops/manifests/rocketchat-mongodb.yaml`).
4.  Delete the stuck MongoDB pod to force a restart:
    ```bash
    kubectl delete pod rocketchat-mongodb-0 -n rocketchat
    ```
5.  Once MongoDB is Running, restart dependent microservices if they are crash-looping:
    ```bash
    kubectl delete pod -n rocketchat -l app.kubernetes.io/name=rocketchat-account
    kubectl delete pod -n rocketchat -l app.kubernetes.io/name=rocketchat-authorization
    kubectl delete pod -n rocketchat -l app.kubernetes.io/name=rocketchat-ddp-streamer
    kubectl delete pod -n rocketchat -l app.kubernetes.io/name=rocketchat-presence
    kubectl delete pod -n rocketchat -l app.kubernetes.io/name=rocketchat-stream-hub
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
