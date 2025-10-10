# Monitoring & Observability Guide

Comprehensive guide for monitoring Rocket.Chat with Grafana Cloud using Prometheus Agent v3.0.0.

---

## Overview

```
Rocket.Chat Pods → Prometheus Agent v3.0.0 → Grafana Cloud (Metrics)
```

**What we monitor:**
- 📈 Application metrics (requests, errors, latency)
- 💾 MongoDB performance (queries, connections, cache)
- 🔄 NATS messaging (throughput, queues)
- ☸️ Kubernetes cluster (pods, nodes, resources)

**Resource usage:** 256-512Mi RAM for Prometheus Agent

---

## Quick Start

### Prerequisites

1. **Grafana Cloud account** (free tier: 10k metrics, 50GB logs, 50GB traces)
2. **Grafana Cloud credentials**:
   - Username/Instance ID (numeric, e.g., "2620155")
   - API Key (starts with `glc_`)

### 1. Get Grafana Cloud Credentials

1. Go to [Grafana Cloud](https://grafana.com/products/cloud/) and sign up
2. Create a stack (e.g., "rocketchat-lab")
3. Navigate to **Prometheus** → **Details**
4. Copy:
   - **Remote Write Endpoint** (e.g., `https://prometheus-prod-XX-prod-REGION.grafana.net/api/prom/push`)
   - **Username/Instance ID**
   - **Password/API Key**

### 2. Create Kubernetes Secret

```bash
kubectl create namespace monitoring

kubectl create secret generic grafana-cloud-credentials \
  --namespace monitoring \
  --from-literal=username="YOUR_INSTANCE_ID" \
  --from-literal=password="YOUR_API_KEY"

# Verify
kubectl get secret -n monitoring grafana-cloud-credentials
```

### 3. Choose Deployment Method

We provide **two deployment options**:

---

## Deployment Option 1: Raw Manifests (Recommended for Lab)

**Best for:** Lab environments, testing, small deployments

**Pros:**
- ✅ Lightweight (~256-512Mi RAM)
- ✅ Fast deployment (~1 minute)
- ✅ No Helm required
- ✅ Easy to customize

### Deploy

```bash
# 1. Update Grafana Cloud endpoint (if needed)
nano manifests/prometheus-agent-configmap.yaml
# Update: remote_write.url with your endpoint

# 2. Deploy all manifests
kubectl apply -f manifests/

# 3. Verify
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app=prometheus-agent
```

### Configuration Files

- **`manifests/prometheus-agent-configmap.yaml`** - Prometheus config with scrape rules
- **`manifests/prometheus-agent-deployment.yaml`** - Prometheus Agent deployment
- **`manifests/prometheus-agent-rbac.yaml`** - ServiceAccount and RBAC
- **`manifests/servicemonitor-crd.yaml`** - ServiceMonitor CRD (optional)

See [manifests/README.md](../manifests/README.md) for detailed instructions.

---

## Deployment Option 2: Helm Chart (Production)

**Best for:** Production environments, large deployments

**Pros:**
- ✅ Full Prometheus Operator stack
- ✅ Includes kube-state-metrics + node-exporter
- ✅ ServiceMonitor/PodMonitor CRD support
- ✅ Easy upgrades via Helm

**Note:** Requires more resources (~1-2Gi total RAM)

### Deploy

```bash
# 1. Update Grafana Cloud endpoint
nano values-monitoring.yaml
# Update: prometheus.prometheusSpec.remoteWrite[0].url

# 2. Add Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 3. Deploy
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f values-monitoring.yaml

# 4. Verify
kubectl get pods -n monitoring
```

---

## Verification

### Check Deployment

```bash
# Check pods
kubectl get pods -n monitoring

# For Helm deployment, check the StatefulSet
kubectl get statefulset -n monitoring

# Check logs
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --tail=100

# Check remote write status
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus \
  | grep -i "remote_write"

# Verify no 429 rate limit errors
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=5m \
  | grep "429" || echo "✅ No rate limit errors"
```

### Check ServiceMonitors

```bash
# List all ServiceMonitors (should only show rocketchat namespace)
kubectl get servicemonitor -A

# Expected output:
# NAMESPACE    NAME                       AGE
# rocketchat   rocketchat-main            Xh
# rocketchat   rocketchat-microservices   Xh
# rocketchat   rocketchat-mongodb         Xh
# rocketchat   rocketchat-nats            Xh

# Verify targets are being scraped
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep -o '"scrapePool":"serviceMonitor/rocketchat[^"]*"' | sort -u

# Check all targets are healthy
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep '"health":"up"' | grep 'rocketchat' | wc -l
# Should return: 4 or more
```

### Verify in Grafana Cloud

1. Log in to Grafana Cloud
2. Go to **Explore** → Select **Prometheus** datasource
3. **Set time range to "Last 15 minutes"**

**Working queries (confirmed):**
```promql
# Check all services by cluster
sum by (job) (up{cluster="rocketchat-k3s-lab"})

# Count by job and instance
sum by (job,instance) (up{cluster="rocketchat-k3s-lab"})

# View top metrics
topk(50, count by (__name__) ({cluster="rocketchat-k3s-lab"}))

# Count available labels
count by (job) (up)
count by (cluster) (up)
```

**Note:** Prometheus Agent mode does NOT store metrics locally, so you cannot query `http://localhost:9090` for actual metrics. All data is immediately forwarded to Grafana Cloud via `remote_write`.

**Expected results:**
- `job` labels: `rocketchat`, `mongodb`, `nats`
- `cluster` label: `rocketchat-k3s-lab`
- All `up` metrics should show value `1` (healthy)

### Remote Write Statistics

```bash
# Check successful sample delivery
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_total"

# Check for failures (should be 0)
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_failed_total"

# Check pending queue (should be low, < 1000)
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_pending"
```

**Healthy indicators:**
- `prometheus_remote_storage_samples_failed_total` = 0
- `prometheus_remote_storage_samples_pending` < 500
- `prometheus_remote_storage_sent_batch_duration_seconds_count` increasing
- No 429 errors in logs

---

## 🎯 Current Production Configuration (Grafana Cloud Free Tier)

### Overview
Our monitoring setup is optimized for Grafana Cloud Free Tier (1,500 samples/s limit):

**Active ServiceMonitors (4 total):**
- `rocketchat-main` - Rocket.Chat application metrics (port 9100)
- `rocketchat-microservices` - Moleculer microservices (port 9458)
- `rocketchat-mongodb` - MongoDB exporter (port 9216)
- `rocketchat-nats` - NATS messaging exporter (port 7777)

**Ingestion Rate:** ~200-400 samples/s (well under 1,500 limit) ✅

### Configuration File: `values-rc-only.yaml`

This is the production Helm values file that prevents rate limiting:

```yaml
alertmanager:
  enabled: false

grafana:
  enabled: false

# Disable all high-volume K8s monitoring
kubeApiServer:
  enabled: false
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
kubeEtcd:
  enabled: false
kubeStateMetrics:
  enabled: false
nodeExporter:
  enabled: false
coreDns:
  enabled: false
kubelet:
  enabled: false

defaultRules:
  create: false

prometheusOperator:
  serviceMonitor:
    selfMonitor: false

prometheus:
  enabled: true
  agentMode: true
  serviceMonitor:
    selfMonitor: false
  prometheusSpec:
    scrapeInterval: 60s
    evaluationInterval: 60s
    externalLabels:
      cluster: rocketchat-k3s-lab
      environment: lab

    # No pod annotation-based scraping
    additionalScrapeConfigs: []

    remoteWrite:
      - url: https://prometheus-prod-55-prod-gb-south-1.grafana.net/api/prom/push
        basicAuth:
          username:
            name: grafana-cloud-credentials
            key: username
          password:
            name: grafana-cloud-credentials
            key: password
        metadataConfig:
          send: false
        sendExemplars: false
        sendNativeHistograms: false
        queueConfig:
          maxShards: 1
          maxSamplesPerSend: 200
          capacity: 10000
        writeRelabelConfigs:
          - action: keep
            sourceLabels: [job]
            regex: rocketchat|mongodb|nats

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
    storageSpec: {}
```

### Key Settings Explained

1. **`additionalScrapeConfigs: []`** - Removes pod annotation-based scraping (prevents duplicates)
2. **`writeRelabelConfigs`** - Safety filter that ONLY sends `job=rocketchat|mongodb|nats` to Grafana Cloud
3. **All K8s components disabled** - No kubelet, kube-state-metrics, node-exporter (prevents high-volume scraping)
4. **`maxShards: 1`, `maxSamplesPerSend: 200`** - Conservative queue settings for free tier
5. **Metadata disabled** - Reduces overhead (`metadataConfig: {send: false}`)

### Apply Configuration

```bash
# Deploy or upgrade monitoring stack
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-rc-only.yaml

# Wait for rollout
kubectl rollout status statefulset/prom-agent-monitoring-kube-prometheus-prometheus -n monitoring

# Verify only Rocket.Chat jobs exist
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  cat /etc/prometheus/config_out/prometheus.env.yaml 2>/dev/null \
  | grep "job_name:" | sort -u
```

### Verification Commands

```bash
# Check active scrape pools (should only show 4 rocketchat ServiceMonitors)
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep -o '"scrapePool":"[^"]*"' | sort -u

# Expected output:
# "scrapePool":"serviceMonitor/rocketchat/rocketchat-main/0"
# "scrapePool":"serviceMonitor/rocketchat/rocketchat-microservices/0"
# "scrapePool":"serviceMonitor/rocketchat/rocketchat-mongodb/0"
# "scrapePool":"serviceMonitor/rocketchat/rocketchat-nats/0"

# Check for duplicate scrapes (each instance should appear once)
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep '"namespace":"rocketchat"' | grep -o '"instance":"[^"]*"' | sort | uniq -c

# Verify remote write is working
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "prometheus_remote_storage_(samples_total|samples_failed_total|samples_pending)"
```

### Verify in Grafana Cloud

1. Log in to Grafana Cloud
2. Go to **Explore** → Select **Prometheus** datasource
3. **Set time range to "Last 15 minutes"**

**Verified working queries:**
```promql
# Check all services are up (grouped by job)
sum by (job) (up{cluster="rocketchat-k3s-lab"})

# See all job and instance combinations
sum by (job,instance) (up{cluster="rocketchat-k3s-lab"})

# View top 50 metric names being ingested
topk(50, count by (__name__) ({cluster="rocketchat-k3s-lab"}))

# Count metrics by label
count by (job) (up)
count by (cluster) (up)
```

**Important Notes:**
- ⚠️ Direct instance queries like `up{instance="10.42.0.50:9100"}` may not work due to label relabeling
- ⚠️ Namespace labels (`namespace="rocketchat"`) may be renamed or dropped during remote write
- ✅ Always use `cluster` label for filtering: `{cluster="rocketchat-k3s-lab"}`
- ✅ Use aggregation functions: `sum by (job) (...)` instead of direct queries

---

## ⚠️ Common Issues After Deployment

### Issue: 401 Unauthorized Authentication Error

**Symptoms:**
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -c prometheus | grep 401
# ERROR: 401 Unauthorized: authentication error: invalid scope requested
```

**Cause:** Grafana Cloud API key has **read-only permissions** instead of **write/push permissions**.

**Solution:**

1. **Generate new API key** in Grafana Cloud with **MetricsPublisher** role
2. **Update secret:**
   ```bash
   kubectl delete secret grafana-cloud-credentials -n monitoring
   kubectl create secret generic grafana-cloud-credentials \
     --namespace monitoring \
     --from-literal=username="YOUR_INSTANCE_ID" \
     --from-literal=password="YOUR_NEW_WRITE_KEY"
   ```
3. **Restart Prometheus:**
   ```bash
   # For Helm deployment
   kubectl rollout restart statefulset prom-agent-monitoring-kube-prometheus-prometheus -n monitoring
   
   # For raw manifests
   kubectl delete pod -n monitoring -l app=prometheus-agent
   ```
4. **Verify:**
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -c prometheus | grep "Done replaying WAL"
   # Should show successful WAL replay with no 401 errors
   ```

See [Issue #18 in troubleshooting.md](troubleshooting.md#issue-18-grafana-cloud-401-unauthorized-authentication-error) for complete details.

---

## Successful Deployment Evidence

### Real Deployment (October 9, 2025)

**Environment:**
- k3s v1.33.5 on Ubuntu
- 4 vCPU, 8 GiB RAM
- Domain: k8.canepro.me

**Deployment Results:**
- ✅ All 4 monitoring pods Running
- ✅ Resource usage: ~255Mi total (well within limits)
- ✅ WAL replay: 5.9 seconds
- ✅ No authentication errors after API key fix
- ✅ Metrics flowing to Grafana Cloud

**Timeline:**
- Initial deployment: 3-5 minutes
- API key issue identified: 5 minutes
- Fix and verification: 5 minutes
- **Total: ~15 minutes**

See [deployment-summary.md](deployment-summary.md) for complete timeline.

---

## Rocket.Chat ServiceMonitors

After deploying the monitoring stack, you need to create ServiceMonitors to enable Prometheus to scrape Rocket.Chat-specific metrics.

### Deploy ServiceMonitors

```bash
# Apply the ServiceMonitor manifests
kubectl apply -f manifests/rocketchat-servicemonitors.yaml

# Verify ServiceMonitors are created
kubectl get servicemonitor -n rocketchat
```

### What Gets Monitored

The ServiceMonitors will scrape metrics from:

1. **Rocket.Chat Main Application** (port 9100)
   - Service: `rocketchat-rocketchat`
   - Metrics: Application performance, HTTP requests, etc.

2. **Rocket.Chat Microservices** (port 9458)
   - Services: `rocketchat-account`, `rocketchat-authorization`, `rocketchat-presence`, `rocketchat-stream-hub`
   - Metrics: Microservice-specific performance metrics

3. **MongoDB Metrics** (port 9216)
   - Service: `rocketchat-mongodb-metrics`
   - Metrics: Database performance, connection stats, query metrics

4. **NATS Metrics** (port 8222)
   - Service: `rocketchat-nats-metrics`
   - Metrics: Message queue performance, connection stats

### Verify Metrics in Grafana Cloud

After applying ServiceMonitors, wait 1-2 minutes, then check these queries:

```promql
# Rocket.Chat application metrics
up{cluster="rocketchat-k3s-lab", job="rocketchat-main"}

# Microservices metrics
up{cluster="rocketchat-k3s-lab", job="rocketchat-microservices"}

# MongoDB metrics
up{cluster="rocketchat-k3s-lab", job="rocketchat-mongodb"}

# NATS metrics
up{cluster="rocketchat-k3s-lab", job="rocketchat-nats"}

# Look for specific Rocket.Chat metrics
rocketchat_*

# MongoDB-specific metrics
mongodb_*

# NATS-specific metrics
nats_*
```

### Troubleshooting ServiceMonitors

If metrics don't appear:

1. **Check ServiceMonitor status:**
   ```bash
   kubectl describe servicemonitor -n rocketchat
   ```

2. **Verify Prometheus targets:**
   ```bash
   # Port-forward to Prometheus UI
   kubectl port-forward -n monitoring svc/prom-agent-monitoring-kube-prometheus-prometheus 9090:9090
   # Then visit http://localhost:9090/targets
   ```

3. **Check Prometheus logs:**
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -c prometheus | grep -i "rocketchat"
   ```

---

## Import Dashboards

### Recommended Grafana Dashboards

- **[Rocket.Chat Metrics](https://grafana.com/grafana/dashboards/23428)** - ID: 23428
- **[Microservice Metrics](https://grafana.com/grafana/dashboards/23427)** - ID: 23427
- **[MongoDB Global (v2)](https://grafana.com/grafana/dashboards/23712)** - ID: 23712

### Manual Import (via UI)

1. In Grafana Cloud, go to **Dashboards** → **New** → **Import**
2. Enter dashboard ID: `23428`
3. Select your **Prometheus** data source
4. Click **Import**
5. Repeat for IDs: `23427`, `23712`

### Automated Import (via Script)

```bash
export GRAFANA_URL="https://YOUR_STACK.grafana.net"
export GRAFANA_API_KEY="YOUR_API_KEY"
export GRAFANA_DATASOURCE="Prometheus"

./scripts/import-grafana-dashboards.sh
```

---

## Configuration

### Scrape Configuration

**What's scraped by default:**

```yaml
scrape_configs:
  # Kubernetes pods with prometheus.io/scrape: "true" annotation
  - job_name: 'kubernetes-pods'
    
  # Kubernetes services with prometheus.io/scrape: "true" annotation
  - job_name: 'kubernetes-services'
    
  # Kubernetes node metrics
  - job_name: 'kubernetes-nodes'
```

**Rocket.Chat pods** have these annotations:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9100"    # Main metrics
  prometheus.io/path: "/metrics"
```

**Microservice pods** expose metrics on port **9458**.

### Customize Scrape Interval

**For Raw Manifests:**
Edit `manifests/prometheus-agent-configmap.yaml`:
```yaml
global:
  scrape_interval: 30s  # Change to 60s for less frequent scraping
```

**For Helm:**
Edit `values-monitoring.yaml`:
```yaml
prometheus:
  prometheusSpec:
    scrapeInterval: 30s  # Change to 60s
```

### Add Custom Scrape Targets

**For Raw Manifests:**
Edit `manifests/prometheus-agent-configmap.yaml` and add:
```yaml
scrape_configs:
  - job_name: 'my-custom-app'
    static_configs:
      - targets: ['my-app.namespace.svc:8080']
```

**For Helm:**
Edit `values-monitoring.yaml` and add:
```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'my-custom-app'
        static_configs:
          - targets: ['my-app.namespace.svc:8080']
```

### Adjust Resource Limits

**For Raw Manifests:**
Edit `manifests/prometheus-agent-deployment.yaml`:
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "200m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

**For Helm:**
Edit `values-monitoring.yaml`:
```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

---

## Troubleshooting

### No Metrics in Grafana Cloud

**Check agent logs:**
```bash
kubectl logs -n monitoring -l app=prometheus-agent | grep -E "error|failed" -i
```

**Common issues:**
- ❌ Wrong Grafana Cloud credentials
- ❌ Incorrect remote_write URL
- ❌ Secret not found
- ❌ Network connectivity issues

**Fix:**
```bash
# Verify secret
kubectl get secret -n monitoring grafana-cloud-credentials -o yaml

# Recreate secret if needed
kubectl delete secret grafana-cloud-credentials -n monitoring
kubectl create secret generic grafana-cloud-credentials \
  --namespace monitoring \
  --from-literal=username="YOUR_ID" \
  --from-literal=password="YOUR_KEY"

# Restart agent
kubectl rollout restart deployment prometheus-agent -n monitoring
```

### Agent Not Scraping Targets

**Check scrape targets:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring deployment/prometheus-agent 9090:9090

# Open: http://localhost:9090/targets
```

**Verify pod annotations:**
```bash
kubectl get pods -n rocketchat -o yaml | grep -A 5 "annotations:"
```

Should see:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9100"
  prometheus.io/path: "/metrics"
```

### High Memory Usage

**Check actual usage:**
```bash
kubectl top pod -n monitoring
```

**If using more than 512Mi:**
- Reduce scrape frequency (60s instead of 30s)
- Increase limits in deployment/values
- Check for metric explosion (too many labels)

### Remote Write Failing

**Check logs:**
```bash
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus \
  | grep -i "remote_write"
```

**Common errors:**
- `401 Unauthorized` - Wrong credentials (need write-enabled API key)
- `429 Too Many Requests` - Rate limiting (see Issue #19 in troubleshooting.md)
- `Connection refused` - Network/firewall issue

### Issue: HTTP 429 Rate Limiting

**Symptoms:**
```bash
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus | grep "429"
# ERROR: HTTP status 429 Too Many Requests: tenant exceeded the ingestion rate limit
```

**Root Cause:**
- Grafana Cloud Free Tier limit: **1,500 samples/second**
- Default K8s monitoring (kubelet, kube-state-metrics, node-exporter): **3,000-5,000 samples/s**
- Rocket.Chat metrics alone: **~200-400 samples/s**

**Solution:**
1. Use the `values-rc-only.yaml` configuration (see above) which:
   - Disables all K8s infrastructure monitoring
   - Keeps only Rocket.Chat, MongoDB, and NATS metrics
   - Adds `writeRelabelConfigs` safety filter
   
2. Apply the configuration:
   ```bash
   helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
     -n monitoring -f values-rc-only.yaml
   ```

3. Delete any lingering high-volume ServiceMonitors:
   ```bash
   kubectl delete servicemonitor -n monitoring \
     monitoring-kube-prometheus-kubelet \
     monitoring-kube-state-metrics \
     monitoring-prometheus-node-exporter 2>/dev/null || true
   ```

4. Verify 429 errors stop:
   ```bash
   kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=5m \
     | grep "429" || echo "✅ No 429 errors"
   ```

See [Issue #19 in troubleshooting.md](troubleshooting.md#issue-19-grafana-cloud-rate-limiting-http-429---resolved) for complete details and timeline.

**Result:** Ingestion rate drops from ~3,000-5,000 samples/s to ~200-400 samples/s, well under the 1,500 limit.

---

## Comparison: Raw Manifests vs Helm

| Feature | Raw Manifests | Helm Chart |
|---------|---------------|------------|
| **Deployment** | `kubectl apply -f manifests/` | `helm install ...` |
| **Complexity** | Simple | More complex |
| **Time** | ~1 minute | ~3-5 minutes |
| **Memory** | 256-512Mi | 1-2Gi |
| **Components** | Prometheus Agent only | Agent + kube-state-metrics + node-exporter |
| **Upgrades** | Manual (`kubectl apply`) | Easy (`helm upgrade`) |
| **CRDs** | Optional | Included |
| **Best For** | Labs, small setups | Production, large setups |

---

## Migration Between Methods

### From Raw Manifests to Helm

```bash
# 1. Delete raw deployment
kubectl delete -f manifests/

# 2. Deploy via Helm
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f values-monitoring.yaml
```

### From Helm to Raw Manifests

```bash
# 1. Uninstall Helm release
helm uninstall monitoring -n monitoring

# 2. Deploy raw manifests
kubectl apply -f manifests/
```

**Note:** The Grafana Cloud secret persists, no need to recreate.

---

## Current Architecture

```
┌─────────────────┐
│  Rocket.Chat    │ :9100, :9458 (metrics endpoints)
│  + Microservices│
└────────┬────────┘
         │
         ├─────────┐
         │         │
    ┌────▼────┐ ┌─▼──────┐
    │ MongoDB │ │  NATS  │ (built-in metrics)
    │ Metrics │ │ Metrics│
    └────┬────┘ └─┬──────┘
         │        │
         └────┬───┘
              │
     ┌────────▼─────────┐
     │ Prometheus Agent │ (scrapes every 30s)
     │    v3.0.0        │
     └────────┬─────────┘
              │ remote_write
              │
     ┌────────▼─────────┐
     │  Grafana Cloud   │
     │   - Prometheus   │ (stores metrics)
     │   - Dashboards   │ (visualizes)
     │   - Alerts       │ (optional)
     └──────────────────┘
```

---

## Future: Full Observability Stack

**Want metrics + logs + traces?**

See **[Observability Roadmap](observability-roadmap.md)** for migration to Grafana Alloy.

**What you'll gain:**
- 📊 **Metrics** - Current functionality (already have)
- 📝 **Logs** - Search and analyze application logs
- 🔍 **Traces** - End-to-end request tracking
- 🔗 **Correlation** - Jump from metric → log → trace

**Timeline:** After Rocket.Chat is stable (2-4 weeks), migrate from Prometheus Agent to Grafana Alloy.

---

## Best Practices

### For Lab Environments
- ✅ Use raw manifests (simpler)
- ✅ Keep scrape interval at 30s
- ✅ Monitor resource usage
- ✅ Start with default limits (256-512Mi)

### For Production
- ✅ Use Helm chart (easier upgrades)
- ✅ Configure retention policies in Grafana Cloud
- ✅ Set up alert rules
- ✅ Increase resources (512Mi-1Gi)
- ✅ Use ServiceMonitor/PodMonitor CRDs
- ✅ Enable high availability (multiple replicas)

---

## Additional Resources

- **[Prometheus Agent Mode](https://prometheus.io/docs/prometheus/latest/feature_flags/#prometheus-agent)** - Official documentation
- **[Grafana Cloud](https://grafana.com/docs/grafana-cloud/)** - Grafana Cloud docs
- **[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)** - Helm chart
- **[Rocket.Chat Dashboards](https://grafana.com/grafana/dashboards/?search=rocket.chat)** - Pre-built dashboards
- **[manifests/README.md](../manifests/README.md)** - Raw manifests deployment guide
- **[Observability Roadmap](observability-roadmap.md)** - Future: logs + traces

---

## Support

For issues or questions:
1. Check [troubleshooting.md](troubleshooting.md) - Issue #5
2. Review [manifests/README.md](../manifests/README.md)
3. Check Grafana Cloud status
4. Open a GitHub issue

---

**Last Updated:** October 9, 2025  
**Version:** 1.0

