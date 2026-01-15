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

## 🗄️ MongoDB: Recommended Deployment (Official MongoDB Kubernetes Operator)

Rocket.Chat has indicated the bundled MongoDB dependency will be removed and should not be used going forward (Bitnami images are no longer produced; security/maintenance concerns). The recommended approach is to run MongoDB independently and point Rocket.Chat at it.

**Reference guide (community, aligns with Rocket.Chat direction)**: `https://gist.github.com/geekgonecrazy/5fcb04aacadaa310aed0b6cc71f9de74`

### What this repo does

- **Disables bundled MongoDB** in `values.yaml` (`mongodb.enabled=false`)
- **Uses `existingMongodbSecret`** so Rocket.Chat reads `MONGO_URL` from a Secret key named `mongo-uri` (credentials are not stored in git)
- **Stops deploying the legacy Bitnami MongoDB** manifests from `ops/` (removed from `ops/kustomization.yaml`)

### GitOps install outline (AKS)

1. **Install the MongoDB operator (Helm)**
   - ArgoCD Application manifest (pinned chart version):
     - `GrafanaLocal/argocd/applications/aks-rocketchat-mongodb-operator.yaml`

2. **Create the operator Secrets (credentials)**
   - Do **NOT** commit credentials to git.
   - Create:
     - `mongodb-admin-password`
     - `mongodb-rocketchat-password`
     - `metrics-endpoint-password`
     - `admin-scram-credentials`
     - `rocketchat-scram-credentials`

3. **Create a `MongoDBCommunity` resource**
   - Start from:
     - `ops/manifests/mongodb-community.example.yaml`
   - Ensure `storageClassName` matches AKS (we use `managed-premium` by default).

4. **Create Rocket.Chat external Mongo secret**
   - Create a Secret named `rocketchat-mongodb-external` in namespace `rocketchat` with key `mongo-uri`.
   - Rocket.Chat chart reads `mongo-uri` into `MONGO_URL`.

### Notes

- **Ingress**: This repo uses Traefik (`ingress.ingressClassName: traefik`) and does not recommend nginx ingress.
- **Monitoring**: Keep the existing monitoring deploy in `ops/` (Prometheus Agent, PodMonitor CRD, ServiceMonitors).

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

### Validate Tracing End-to-End (Tracegen → OTel Collector → Tempo)
**Purpose**
- Generate synthetic traces on-demand to validate the entire tracing pipeline and Grafana Tempo Explore queries.

**Where it lives (GitOps)**
- Trace generator job: `ops/manifests/otel-tracegen-job.yaml`
- OTel Collector config: `ops/manifests/otel-collector-configmap.yaml`

**How it works**
- The Job runs `telemetrygen` for ~60s at ~5 spans/sec and sends OTLP/gRPC to:
  - `otel-collector.monitoring.svc.cluster.local:4317`
- The collector exports traces to the hub Tempo via the `otlphttp/oke` exporter.

**Run it (GitOps rerun)**
1. Edit `ops/manifests/otel-tracegen-job.yaml`
   - **Bump the Job name** (Jobs are immutable; a new name = a new run).
   - **Bump** `canepro.me/otel-tracegen-rev` (for bookkeeping).
2. Commit + push to `master`. ArgoCD will create the new Job and prune old runs (by default).

**Verify (cluster-side)**
```bash
kubectl --context k8-canepro-me -n monitoring get pods | grep -i tracegen
kubectl --context k8-canepro-me -n monitoring logs job/<job-name>
kubectl --context k8-canepro-me -n monitoring logs deploy/otel-collector --since=5m | grep -iE '(traces|otlphttp|error|dropped|404)'
```

**Verify in Grafana (Tempo Explore)**
- Explore → Tempo → Search:
  - **Service name**: `rocket-chat` (our collector upserts `service.name` to this)
  - Typical operation from tracegen: `lets-go`
- If the Service dropdown is empty, use TraceQL:
  - `{ resource.service.name = "rocket-chat" }`

**Pin telemetrygen image for reproducible runs**
- Prefer pinning to a digest (example):
  - `image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen@sha256:<digest>`

**Common failures we hit**
- **GHCR 403 (anonymous token forbidden)**: Image pull fails from `ghcr.io/token?... 403`.
  - Fix: use a different image reference/registry or add `imagePullSecrets` if your environment blocks anonymous pulls.
- **Image tag not found**: `...telemetrygen:<tag>: not found`.
  - Fix: use an existing tag or pin to a digest from a known-good run.
- **Tempo export 404**: collector logs show:
  - `... responded with HTTP Status Code 404`
  - Fix: ensure `otlphttp/oke.endpoint` is the **base URL** expected by the hub; the exporter appends `/v1/traces`.
- **ArgoCD CLI token expired**
  - `argocd login argocd.canepro.me --grpc-web`

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
