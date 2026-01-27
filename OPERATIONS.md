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

## 🔐 ArgoCD CLI Login and Application Management

### Login to ArgoCD

ArgoCD CLI is used to manage applications when auto-sync is disabled or for manual synchronization.

**Server URL**: `https://argocd.canepro.me`

**Login command**:
```bash
argocd login argocd.canepro.me --grpc-web
```
- The `--grpc-web` flag is required when ArgoCD is behind an ingress/proxy that breaks standard gRPC
- You'll be prompted for username (default: `admin`) and password

**Get initial admin password** (if needed):
```bash
# If ArgoCD is running on AKS cluster
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# If ArgoCD is running on OKE hub cluster
kubectl --context oke-cluster -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

### List Applications

```bash
argocd app list
```

### Sync Applications

**Sync a specific application**:
```bash
argocd app sync aks-rocketchat-ops
argocd app sync aks-rocketchat-helm
argocd app sync aks-rocketchat-secrets
argocd app sync aks-rocketchat-external-secrets
argocd app sync aks-rocketchat-mongodb-operator
argocd app sync aks-traefik
```

**Sync with prune** (removes resources not in Git):
```bash
argocd app sync aks-rocketchat-ops --prune
```

**Force refresh and sync** (if ArgoCD isn't detecting Git changes):
```bash
argocd app refresh aks-rocketchat-ops
argocd app sync aks-rocketchat-ops
```

### Check Application Status

```bash
argocd app get aks-rocketchat-ops
```

### Troubleshooting Login Issues

- **Token expired**: Re-run `argocd login argocd.canepro.me --grpc-web`
- **Connection refused**: Verify you can reach `https://argocd.canepro.me` and that ArgoCD is running
- **gRPC errors**: Always use `--grpc-web` flag when ArgoCD is behind ingress/proxy

## 💰 Cost Optimization: AKS Cluster Scheduling

The AKS cluster uses **Azure Automation** to automatically start and stop on a schedule, significantly reducing costs.

### Current Schedule (2026-01-25)

- **Start Time**: 16:00 (4 PM) on weekdays
- **Stop Time**: 23:00 (11 PM) on weekdays
- **Weekends**: Cluster stays off
- **Runtime**: ~7 hours/day × 5 weekdays = ~35 hours/week = ~140 hours/month
- **Estimated Monthly Cost**: ~£55-70 (within £90/month budget)

### Manual Cluster Control

If you need the cluster during off-hours:

```bash
# Start cluster manually
az aks start --resource-group rg-canepro-aks --name aks-canepro

# Stop cluster manually
az aks stop --resource-group rg-canepro-aks --name aks-canepro

# Check cluster power state
az aks show --name aks-canepro --resource-group rg-canepro-aks --query "powerState" --output table
```

### Updating the Schedule

To change the schedule times:

1. **Update `terraform.tfvars`** (in Cloud Shell):
   ```bash
   cd ~/rocketchat-k8s/terraform
   nano terraform.tfvars
   # Update: startup_time = "16:00" (or desired time)
   # Update: shutdown_time = "23:00" (or desired time)
   ```

2. **Temporarily remove `ignore_changes`** in `terraform/automation.tf`:
   - Comment out `ignore_changes = [start_time]` for the schedule you want to update

3. **Apply the change**:
   ```bash
   terraform plan  # Verify changes
   terraform apply
   ```

4. **Restore `ignore_changes`** after applying (to prevent future updates)

**Note:** See [`terraform/README.md`](terraform/README.md) for detailed instructions and cost savings breakdown.

### Cost Savings

- **Previous schedule** (08:30-23:00): ~72.5 hours/week ≈ £200/month
- **Current schedule** (16:00-23:00): ~35 hours/week ≈ £55-70/month
- **Savings**: ~52% reduction, saving ~£75-88/month

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
4.  **Cluster Stopped**: If pods are not starting, check if the cluster is running:
    ```bash
    az aks show --name aks-canepro --resource-group rg-canepro-aks --query "powerState" --output table
    # If "Stopped", start it manually or wait for scheduled start time
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

2. **Provide credentials (GitOps-friendly)**
   - Do **NOT** commit plaintext credentials to git.
   - Recommended (Azure): **External Secrets Operator + Azure Key Vault**.
   - Minimum required Secrets (names referenced by `MongoDBCommunity`):
     - `mongodb-admin-password` (key: `password`)
     - `mongodb-rocketchat-password` (key: `password`)
     - `metrics-endpoint-password` (key: `password`)
   - Notes:
     - The operator generates SCRAM credential Secrets itself based on `scramCredentialsSecretName`.
     - Do **not** manually create SCRAM Secrets unless you know the exact expected format.

3. **Create a `MongoDBCommunity` resource**
   - Start from:
     - `ops/manifests/mongodb-community.example.yaml`
   - Ensure `storageClassName` matches AKS (we use `managed-premium` by default).

4. **Rocket.Chat external Mongo Secret (required keys)**
   - Rocket.Chat requires **both** keys in the Secret referenced by `existingMongodbSecret`:
     - `mongo-uri` → used as `MONGO_URL`
     - `mongo-oplog-uri` → used as `MONGO_OPLOG_URL`
   - Secret name used in this repo: `rocketchat-mongodb-external` (namespace: `rocketchat`)
   - GitOps note:
     - Do not create this via `kubectl create secret` long-term; manage it via your secret mechanism (ESO+AKV recommended).

### Notes

- **Ingress**: This repo uses Traefik (`ingress.ingressClassName: traefik`) and does not recommend nginx ingress.
- **Monitoring**: Keep the existing monitoring deploy in `ops/` (Prometheus Agent, PodMonitor CRD, ServiceMonitors).

## 🔐 GitOps-first Secrets (Recommendation)

To make this repo truly GitOps-first, move Secrets out of “manual kubectl creates” and into a managed pattern.

- **Recommended on Azure**: External Secrets Operator + Azure Key Vault
  - Git stores `ExternalSecret` manifests
  - Azure Key Vault stores the secret values
  - ArgoCD syncs the manifests; ESO materializes K8s Secrets

Until this is in place, any manual `kubectl create secret ...` should be treated as **bootstrap-only** and recorded (see `MIGRATION_STATUS.md`).

### Option A Implementation (AKS + Azure Key Vault + External Secrets Operator)

This repo includes a GitOps-first scaffold for **External Secrets Operator (ESO)** + **Azure Key Vault (AKV)** using **Azure Workload Identity**.

#### What gets installed (GitOps)

- **ESO (Helm via ArgoCD)**:
  - `GrafanaLocal/argocd/applications/aks-rocketchat-external-secrets.yaml`
  - Namespace: `external-secrets`
- **ClusterSecretStore + ExternalSecrets (Kustomize via ArgoCD)**:
  - `GrafanaLocal/argocd/applications/aks-rocketchat-secrets.yaml`
  - Manifests: `ops/secrets/`

#### One-time bootstrap (Cloud Shell on work machine)

This must be done from **Azure Portal / Cloud Shell** (per the migration plan restrictions). All secret values are populated via Cloud Shell commands and are **never stored in git**.

##### Step 1: Provision Key Vault infrastructure via Terraform

**From Azure Cloud Shell (work machine only):**

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform (if not already done)
terraform init

# Review the plan (Key Vault + UAMI + RBAC + Key Vault secret values)
terraform plan -out=tfplan

# Apply exactly what you planned
terraform apply tfplan

# Capture outputs needed for GitOps configuration
terraform output -json > /tmp/terraform-outputs.json
cat /tmp/terraform-outputs.json
```

**Record these values** (you'll need them for Step 3):
- `key_vault_name` → `KEYVAULT_NAME`
- `key_vault_uri` → `KEYVAULT_URI` (for reference)
- `eso_identity_client_id` → `UAMI_CLIENT_ID`
- `azure_tenant_id` → `TENANT_ID`

**Note:** Terraform creates the Key Vault, UAMI, RBAC assignment, **and the Key Vault secret values** (from `terraform.tfvars`).  
This means secret values will exist in **Terraform state**; use a secure state backend and restrict access.

##### Step 2: Configure secret values in Terraform (Cloud Shell only)

**From Azure Cloud Shell**, edit `terraform/terraform.tfvars` with your actual secret values:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your actual values
```

**Fill in these variables** (match your current cluster values):
- `rocketchat_mongo_uri` - MongoDB connection string
- `rocketchat_mongo_oplog_uri` - MongoDB oplog connection string
- `mongodb_admin_password` - MongoDB admin password
- `mongodb_rocketchat_password` - MongoDB rocketchat user password
- `mongodb_metrics_endpoint_password` - MongoDB metrics password

**Example `terraform.tfvars`** (placeholders — replace with your actual values):
```hcl
rocketchat_mongo_uri = "mongodb://rocketchat:CHANGE_ME@mongodb-0.mongodb-svc.rocketchat.svc.cluster.local:27017/rocketchat?authSource=rocketchat&replicaSet=mongodb"
rocketchat_mongo_oplog_uri = "mongodb://admin:CHANGE_ME@mongodb-0.mongodb-svc.rocketchat.svc.cluster.local:27017/local?authSource=admin&replicaSet=mongodb"
mongodb_admin_password = "CHANGE_ME"
mongodb_rocketchat_password = "CHANGE_ME"
mongodb_metrics_endpoint_password = "CHANGE_ME"
```

**Important:** 
- `terraform.tfvars` is **gitignored** and should **never** be committed
- Secret values will be created in Key Vault when you run `terraform apply`
- Values are marked `sensitive = true` so they won't appear in Terraform output

##### Step 2.5: Terraform state + Jenkins (future workflow)

We expect Terraform to be managed in a **stateful** way:
- Use the Azure Storage backend (`backend "azurerm" {}` in `terraform/main.tf`) and provide backend values via a local `backend.hcl` file (gitignored).
- Terraform state must be treated as sensitive (it may include Key Vault secret values).

**Jenkins guidance (GitOps-aligned):**
- Jenkins may run **`terraform fmt` / `terraform validate` / `terraform plan`** as PR checks.
- Jenkins should **not** run `terraform apply` unless the organization explicitly changes the current restriction and the pipeline is designed with:
  - manual approvals,
  - remote backend + state locking,
  - least-privilege Azure credentials,
  - and secure handling of `terraform.tfvars` (never stored in git, never echoed to logs).

**Alternative approach (manual secret creation):** If you prefer not to store secrets in Terraform state, you can remove the `azurerm_key_vault_secret` resources from `keyvault.tf` and populate secrets manually after Terraform apply (see `terraform/README.md` for details).

##### Step 3: Create federated credential for Workload Identity

**From Azure Cloud Shell**, link the ESO ServiceAccount to the UAMI:

```bash
# Get AKS OIDC issuer URL
AKS_RESOURCE_GROUP="<your-aks-resource-group>"
AKS_CLUSTER_NAME="<your-aks-cluster-name>"
OIDC_ISSUER=$(az aks show -g "$AKS_RESOURCE_GROUP" -n "$AKS_CLUSTER_NAME" \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

# Get UAMI client ID from Terraform output
UAMI_CLIENT_ID="<from terraform output: eso_identity_client_id>"

# Create federated credential
az identity federated-credential create \
  --name "eso-workload-identity" \
  --identity-name "<UAMI-name-from-terraform>" \
  --resource-group "<your-resource-group>" \
  --issuer "$OIDC_ISSUER" \
  --subject "system:serviceaccount:external-secrets:external-secrets" \
  --audience "api://AzureADTokenExchange"
```

##### Step 4: Update GitOps manifests (non-secret placeholders)

**In your local repo** (not Cloud Shell), update these files with values from Step 1:

1. **`GrafanaLocal/argocd/applications/aks-rocketchat-external-secrets.yaml`**
   - Replace `REPLACE_WITH_UAMI_CLIENT_ID` with `UAMI_CLIENT_ID` from Terraform output

2. **`ops/secrets/clustersecretstore-azure-keyvault.yaml`**
   - Replace `REPLACE_WITH_TENANT_ID` with `TENANT_ID` from Terraform output
   - Replace `REPLACE_WITH_KEYVAULT_NAME` with `KEYVAULT_NAME` from Terraform output

3. **Commit and push** to `master` branch

##### Step 5: Sync ArgoCD applications

**From ArgoCD UI or CLI:**

```bash
# Sync ESO operator first (installs CRDs and controller)
argocd app sync aks-rocketchat-external-secrets

# Wait for ESO to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets \
  -n external-secrets --timeout=300s

# Sync secrets app (creates ClusterSecretStore + ExternalSecrets)
argocd app sync aks-rocketchat-secrets

# Verify secrets were created
kubectl -n rocketchat get secret rocketchat-mongodb-external
kubectl -n rocketchat get externalsecret
```

After this, Kubernetes Secrets like `rocketchat-mongodb-external` will be **continuously reconciled from Key Vault**, eliminating manual `kubectl create secret ...` steps.

**Note:** Secret values are stored **only in Azure Key Vault** and are **never committed to git**. Terraform state may contain resource IDs but not secret values (ensure state backend is secured).

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

### Image Pruning (Weekly)
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

### Stale Pod Cleanup (Daily after Cluster Restart)
The `aks-stale-pod-cleanup` CronJob runs daily at 9:00 AM UTC (30 minutes after cluster auto-start at 8:30) to remove orphaned pods left in terminal states after AKS cluster shutdown/restart cycles.

**What it cleans:**
- `Succeeded` pods (Completed jobs from before shutdown)
- `Failed` pods (Error state pods)
- `Unknown` pods (ContainerStatusUnknown from cluster shutdown)

**Manual cleanup (immediate):**
If you need to clean up stale pods right now:
```bash
# Delete all terminal state pods
kubectl delete pods --field-selector=status.phase=Succeeded -A
kubectl delete pods --field-selector=status.phase=Failed -A
kubectl delete pods --field-selector=status.phase=Unknown -A

# Or run the cleanup job manually
kubectl -n monitoring create job --from=cronjob/aks-stale-pod-cleanup manual-cleanup-$(date +%s)
```

**Verify what will be cleaned:**
```bash
kubectl get pods -A --field-selector=status.phase=Succeeded
kubectl get pods -A --field-selector=status.phase=Failed
kubectl get pods -A --field-selector=status.phase=Unknown
```

**Check cleanup job logs:**
```bash
kubectl -n monitoring get jobs | grep stale-pod-cleanup
kubectl -n monitoring logs job/aks-stale-pod-cleanup-<timestamp>
```

**Note**: This cleanup is safe because:
- Completed pods are from finished jobs that succeeded
- Failed pods are from jobs that already failed and won't recover
- Unknown pods are orphaned containers from cluster shutdown
- Running services have healthy new pods created after cluster restart

### Monitoring Maintenance Jobs (Grafana Dashboard)

A Grafana dashboard is available to monitor all maintenance CronJobs in real-time.

**Dashboard Location**: `ops/manifests/grafana-dashboard-maintenance-jobs.json`

**What it shows**:
- CronJob schedules and status
- Time since last run and next scheduled run
- Job success/failure history
- Job duration trends
- Recent job execution status

**To import the dashboard**:
1. Open Grafana at `https://grafana.canepro.me`
2. Navigate to **Dashboards** → **Import**
3. Click **Upload JSON file**
4. Select `ops/manifests/grafana-dashboard-maintenance-jobs.json`
5. Select your Prometheus datasource
6. Click **Import**

**Dashboard panels include**:
- **Maintenance CronJobs Overview**: All CronJobs with schedules
- **Time Since Last Scheduled Run**: How long since each job ran (alerts if > 2 days)
- **Next Scheduled Run**: When each job will run next
- **Job Execution History**: Success/failure rate over time
- **Job Duration**: How long each job takes to complete
- **Recent Job Status**: Current status of recent job runs

**Recommended alerts** (can be added via Grafana):
- Alert if `aks-stale-pod-cleanup` hasn't run in > 25 hours
- Alert if `k3s-image-prune` hasn't run in > 8 days
- Alert if any maintenance job fails 2+ times in a row

## ⚠️ Known Quirks
- **Secrets**: `rocketchat-rocketchat` secret is managed by Helm but populated via `values.yaml` (externalMongodbUrl) to preserve legacy passwords. Do not delete it manually.
- **Image Prune CronJob**: The `k3s-image-prune` cronjob has a legacy name but works on AKS (uses `crictl` with k3s fallback).
