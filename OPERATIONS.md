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

### Incident: Grafana "Rocket.Chat Metrics" Dashboard shows N/A / No data
**Symptoms**
- Grafana dashboard panels show `N/A` / `No data`
- Dashboard variables (Cluster/Job/Namespace/Domain/Workspace) show `None` or do not populate
- `rocketchat_info` may exist in Explore, but panels still show nothing

**Root causes we hit**
1. **Metrics not enabled / not scraped**
   - Rocket.Chat must expose Prometheus metrics (in our Helm deployment this is configured via `values.yaml`).
2. **Label/schema mismatch between scraped metrics and dashboard filters**
   - The existing Rocket.Chat dashboard filters on labels like `tenant_id`, `namespace`, and `site_url`.
   - Our Kubernetes discovery labels are `cluster` and `kubernetes_namespace` by default.
   - Fix: add compatibility labels in the Prometheus Agent pipeline so the dashboard continues to work without edits.
3. **Prometheus Agent config changes require a restart**
   - `monitoring/prometheus-agent` renders `/etc/prometheus/prometheus.yml` from a template using the `config-init` initContainer into an `emptyDir`.
   - Updating the ConfigMap alone will NOT update the running config until the pod restarts.

**Where changes live (GitOps)**
- Rocket.Chat metrics enablement: `values.yaml`
- Prometheus Agent template + label mapping: `ops/manifests/prometheus-agent-configmap.yaml`
- Prometheus Agent restart trigger: `ops/manifests/prometheus-agent-deployment.yaml` (annotation bump)
- (Note) `ops/manifests/rocketchat-servicemonitors.yaml` exists but does not affect the Prometheus Agent scrape jobs (`kubernetes_sd_configs`).

**Fix steps (high-level)**
1. **Ensure Rocket.Chat exposes metrics**
   - Verify env vars on the Deployment:
     ```bash
     kubectl -n rocketchat describe deploy rocketchat-rocketchat | sed -n '/Environment:/,/Mounts:/p'
     ```
   - Verify Service exposes the metrics port:
     ```bash
     kubectl -n rocketchat describe svc rocketchat-rocketchat
     ```
2. **Ensure Prometheus Agent is labeling metrics for the dashboard**
   - We add/maintain these labels:
     - `workspace` / `domain` (for dashboard variables)
     - compatibility: `tenant_id` (maps to cluster) and `namespace` (copied from `kubernetes_namespace`)
3. **Restart Prometheus Agent to apply ConfigMap template changes**
   - Bump `canepro.me/prometheus-agent-config-rev` in `ops/manifests/prometheus-agent-deployment.yaml` and sync ArgoCD.
   - If using ArgoCD CLI and you see token errors:
     ```bash
     argocd login argocd.canepro.me --grpc-web
     ```

**Verification (must pass)**
1. Prometheus Agent is running the expected config:
   ```bash
   kubectl -n monitoring exec deploy/prometheus-agent -c prometheus -- \
     sh -lc 'sed -n "1,40p" /etc/prometheus/prometheus.yml'
   ```
   Confirm `external_labels` includes `workspace`, `domain`, and `tenant_id`.
2. Grafana Explore shows the compatibility labels on the series:
   - Run:
     - `rocketchat_info{job="kubernetes-services"}`
   - Confirm labels include:
     - `tenant_id="k8-canepro-me"`
     - `namespace="rocketchat"`
     - `site_url="https://k8.canepro.me"`
     - `workspace="production"`
     - `domain="k8.canepro.me"`

**Notes**
- `label_values(...)` is a Grafana variable helper, not PromQL; it will error in Explore. Use e.g.:
  - `count by (workspace) (rocketchat_info)`
  - `count by (domain) (rocketchat_info)`

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
