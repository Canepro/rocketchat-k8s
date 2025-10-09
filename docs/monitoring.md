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

# Check logs
kubectl logs -n monitoring -l app=prometheus-agent

# Check remote write status
kubectl logs -n monitoring -l app=prometheus-agent | grep -i "remote_write"

# Check if scraping
kubectl logs -n monitoring -l app=prometheus-agent | grep -i "scrape"
```

### Verify in Grafana Cloud

1. Log in to Grafana Cloud
2. Go to **Explore** → Select **Prometheus** datasource
3. Query: `up{cluster="rocketchat-k3s"}` or `up{cluster="rocketchat-k3s-lab"}`
4. Should see metrics from Rocket.Chat, MongoDB, NATS, Kubernetes

**Expected metrics:**
```promql
# All targets should be up
up{cluster="rocketchat-k3s-lab"}

# Rocket.Chat specific metrics
rocketchat_version_info

# MongoDB metrics
mongodb_up

# NATS metrics  
nats_server_info

# Kubernetes cluster metrics
kube_node_info
```

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
kubectl logs -n monitoring -l app=prometheus-agent | grep -i "remote_write"
```

**Common errors:**
- `401 Unauthorized` - Wrong credentials
- `429 Too Many Requests` - Rate limiting (check Grafana Cloud limits)
- `Connection refused` - Network/firewall issue

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

