# Monitoring Stack - Final Configuration

**Date:** October 10, 2025  
**Status:** ✅ Operational - Grafana Cloud Free Tier Optimized

---

## 🎯 Summary

The Rocket.Chat monitoring stack is successfully configured and sending metrics to Grafana Cloud, optimized for the free tier's 1,500 samples/second ingestion limit.

### Current State

**Metrics Flow:**
```
Rocket.Chat Pods → ServiceMonitors → Prometheus Agent → Grafana Cloud
                                     (4 targets)      (remote_write)
```

**Ingestion Rate:** ~200-400 samples/s (well under 1,500 limit) ✅  
**Status:** No 429 rate limit errors ✅  
**All Targets:** Healthy and UP ✅  

---

## 📊 Active ServiceMonitors

Only **4 ServiceMonitors** are configured, all in the `rocketchat` namespace:

| ServiceMonitor | Target Service | Port | Job Label | Metrics |
|----------------|----------------|------|-----------|---------|
| `rocketchat-main` | `rocketchat-rocketchat` | 9100 | `rocketchat` | Application metrics (HTTP requests, errors, latency) |
| `rocketchat-microservices` | `rocketchat-rocketchat-monolith-ms-metrics` | 9458 | `rocketchat` | Moleculer microservices metrics |
| `rocketchat-mongodb` | `rocketchat-mongodb-metrics` | 9216 | `mongodb` | MongoDB performance (connections, queries, cache) |
| `rocketchat-nats` | `rocketchat-nats-metrics` | 7777 | `nats` | NATS messaging (connections, messages, throughput) |

**Scrape Interval:** 60 seconds for all targets  
**Scrape Timeout:** 10 seconds  

---

## 🔧 Configuration Files

### Primary Configuration: `values-rc-only.yaml`

This Helm values file is the **source of truth** for the monitoring stack:

**Location:** `rocketchat-k8s/values-rc-only.yaml`

**Key Features:**
1. ✅ Disables all high-volume K8s infrastructure monitoring (kubelet, kube-state-metrics, node-exporter)
2. ✅ Removes pod annotation-based scraping (prevents duplicates)
3. ✅ Adds `writeRelabelConfigs` to filter only `job=rocketchat|mongodb|nats`
4. ✅ Optimizes queue settings for free tier (`maxShards: 1`, `maxSamplesPerSend: 200`)
5. ✅ Disables metadata, exemplars, and native histograms to reduce overhead

**Apply Configuration:**
```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-rc-only.yaml
```

### ServiceMonitor Configurations

**Location:** Created by Rocket.Chat Helm chart deployment

**Applied Patches:**
1. `jobLabel: app.kubernetes.io/name` - Uses app name as Prometheus job label
2. `interval: 60s` - Scrape every 60 seconds (reduced from 30s default)
3. Port-specific targeting:
   - `rocketchat-main`: `port: metrics` (9100)
   - `rocketchat-microservices`: `port: moleculer-metrics` (9458)
   - `rocketchat-mongodb`: `port: http-metrics` (9216)
   - `rocketchat-nats`: `port: metrics` (7777) with relabeling to avoid headless service duplicate

---

## 📈 Grafana Cloud Integration

### Remote Write Configuration

**Endpoint:** `https://prometheus-prod-55-prod-gb-south-1.grafana.net/api/prom/push`  
**Authentication:** Basic Auth via `grafana-cloud-credentials` secret  
**Remote Name:** `032014`  

**Queue Settings:**
- `maxShards: 1` - Single shard (sufficient for low volume)
- `maxSamplesPerSend: 200` - Small batches
- `capacity: 10000` - Queue capacity
- `batchSendDeadline: 5s` - Send every 5 seconds

**Optimizations:**
- `metadataConfig: {send: false}` - Don't send metadata
- `sendExemplars: false` - Don't send exemplars
- `sendNativeHistograms: false` - Don't send native histograms

### External Labels

All metrics are tagged with:
- `cluster: rocketchat-k3s-lab` - Cluster identifier
- `environment: lab` - Environment type

### Write Relabel Configs (Safety Filter)

```yaml
writeRelabelConfigs:
  - action: keep
    sourceLabels: [job]
    regex: rocketchat|mongodb|nats
```

**Purpose:** Even if unwanted ServiceMonitors exist, only metrics with `job=rocketchat`, `job=mongodb`, or `job=nats` will be sent to Grafana Cloud. This is a safety net against accidental high-volume scraping.

---

## ✅ Verification

### Check Local Status

```bash
# Verify only 4 ServiceMonitors exist
kubectl get servicemonitor -A
# Expected: Only rocketchat namespace with 4 ServiceMonitors

# Check scrape pools
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep -o '"scrapePool":"serviceMonitor/rocketchat[^"]*"' | sort -u
# Expected: 4 rocketchat ServiceMonitor pools

# Verify no 429 errors
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=5m \
  | grep "429" || echo "✅ No 429 errors"

# Check remote write stats
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_failed_total"
# Expected: = 0 (no failures)
```

### Grafana Cloud Queries

**⚠️ Important:** Prometheus Agent mode does NOT store metrics locally. All queries must be run in Grafana Cloud.

**Verified Working Queries:**
```promql
# Check all services by job
sum by (job) (up{cluster="rocketchat-k3s-lab"})
# Expected: rocketchat, mongodb, nats = 1

# View all job and instance combinations
sum by (job,instance) (up{cluster="rocketchat-k3s-lab"})

# Top 50 metric names
topk(50, count by (__name__) ({cluster="rocketchat-k3s-lab"}))

# Count by labels
count by (job) (up)
count by (cluster) (up)
```

**Known Limitations:**
- ❌ Direct instance queries don't work: `up{instance="10.42.0.50:9100"}`
- ❌ Namespace queries don't work: `up{namespace="rocketchat"}`
- ❌ Direct metric name queries may not work: `rocketchat_info` (use aggregation instead)
- ✅ Always use `cluster` label: `{cluster="rocketchat-k3s-lab"}`
- ✅ Always use aggregation: `sum by (job) (...)`

---

## 🛠️ Troubleshooting

### Check ServiceMonitor Health

```bash
# Get all ServiceMonitor details
kubectl get servicemonitor -n rocketchat -o yaml

# Check specific ServiceMonitor
kubectl describe servicemonitor rocketchat-main -n rocketchat

# Verify service labels match ServiceMonitor selectors
kubectl get svc rocketchat-rocketchat -n rocketchat --show-labels
kubectl get servicemonitor rocketchat-main -n rocketchat -o yaml | grep -A 5 "selector:"
```

### Check Prometheus Targets

```bash
# Get all active targets
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null

# Check target health
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep -o '"health":"[^"]*"' | sort | uniq -c

# Check for scrape errors
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep '"lastError":"[^"]' | grep -v '"lastError":""'
```

### Common Issues

**Problem: Metrics not appearing in Grafana Cloud**

Check:
1. Time range in Grafana Cloud (set to "Last 15 minutes")
2. Use cluster label: `{cluster="rocketchat-k3s-lab"}`
3. Use aggregation: `sum by (job) (up{cluster="rocketchat-k3s-lab"})`
4. Check `topk()` to see what metrics are actually there

**Problem: 429 Rate Limit Errors**

Solution: Already applied! The `writeRelabelConfigs` and disabled K8s monitoring prevent this.

Verify:
```bash
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=10m \
  | grep "429" || echo "✅ No 429 errors"
```

**Problem: Duplicate Scrapes**

Check for duplicate instances:
```bash
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep '"namespace":"rocketchat"' | grep -o '"instance":"[^"]*"' | sort | uniq -c
```

Each instance should appear 1-2 times max (2 is OK for NATS due to dual service discovery).

---

## 📝 Key Learnings & Decisions

### Why We Removed K8s Infrastructure Monitoring

**Problem:** Default kube-prometheus-stack monitoring generates 3,000-5,000 samples/s:
- kubelet/cAdvisor: ~2,500 samples/s (80% of total)
- kube-state-metrics: ~500 samples/s
- node-exporter: ~300 samples/s
- Other components: ~200 samples/s

**Impact:** Constant HTTP 429 errors from Grafana Cloud free tier (1,500 samples/s limit)

**Solution:** Disabled all K8s infrastructure monitoring, keeping only application-level metrics (Rocket.Chat, MongoDB, NATS).

**Result:** 
- Before: 3,000-5,000 samples/s → Constant 429 errors ❌
- After: ~200-400 samples/s → No errors ✅

### Why We Use writeRelabelConfigs

**Purpose:** Belt-and-suspenders protection against accidental high-volume scraping.

Even if ServiceMonitors are accidentally created or re-enabled by Helm upgrades, the `writeRelabelConfigs` filter ensures only `job=rocketchat|mongodb|nats` metrics reach Grafana Cloud.

**Implementation:**
```yaml
writeRelabelConfigs:
  - action: keep
    sourceLabels: [job]
    regex: rocketchat|mongodb|nats
```

This dropped ingestion from 26 million samples scraped to only 30k samples sent (99.9% filtered).

### Why We Disabled additionalScrapeConfigs

**Problem:** Pod annotation-based scraping (`prometheus.io/scrape: "true"`) created duplicate jobs:
- ServiceMonitor job: `serviceMonitor/rocketchat/rocketchat-nats/0`
- Annotation job: `nats`
- Both scraping the same endpoint (duplicate metrics)

**Solution:** Set `additionalScrapeConfigs: []` and removed all `prometheus.io/*` annotations from pods, services, and controllers.

**Result:** Eliminated duplicate scrape pools and reduced instance duplication from 4x to 1-2x.

---

## 🔄 Maintenance

### Upgrade Monitoring Stack

```bash
# Pull latest Helm chart
helm repo update prometheus-community

# Upgrade (preserves our custom values)
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-rc-only.yaml

# Verify after upgrade
kubectl get servicemonitor -A
# Should still show only rocketchat namespace

# If K8s ServiceMonitors were recreated, delete them
kubectl -n monitoring get servicemonitors -o name \
  | grep -viE 'rocketchat|mongo|nats' \
  | xargs -r kubectl -n monitoring delete
```

### Update ServiceMonitor Intervals

If you need to adjust scrape frequency:

```bash
# Increase to 2 minutes (reduce load further)
kubectl patch servicemonitor rocketchat-main -n rocketchat --type='json' \
  -p='[{"op":"replace","path":"/spec/endpoints/0/interval","value":"2m"}]'

kubectl patch servicemonitor rocketchat-microservices -n rocketchat --type='json' \
  -p='[{"op":"replace","path":"/spec/endpoints/0/interval","value":"2m"}]'

kubectl patch servicemonitor rocketchat-mongodb -n rocketchat --type='json' \
  -p='[{"op":"replace","path":"/spec/endpoints/0/interval","value":"2m"}]'

kubectl patch servicemonitor rocketchat-nats -n rocketchat --type='json' \
  -p='[{"op":"replace","path":"/spec/endpoints/0/interval","value":"2m"}]'
```

### Regenerate Grafana Cloud API Key

If you need to rotate the API key:

```bash
# 1. Generate new key in Grafana Cloud (must have MetricsPublisher role)
# 2. Update secret
kubectl delete secret grafana-cloud-credentials -n monitoring
kubectl create secret generic grafana-cloud-credentials \
  --namespace monitoring \
  --from-literal=username="YOUR_INSTANCE_ID" \
  --from-literal=password="YOUR_NEW_WRITE_KEY"

# 3. Restart Prometheus
kubectl rollout restart statefulset/prom-agent-monitoring-kube-prometheus-prometheus -n monitoring

# 4. Verify
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus \
  | grep -i "error" | tail -20
```

---

## 📊 Metrics Reference

### Available Metrics in Grafana Cloud

Use `topk(50, count by (__name__) ({cluster="rocketchat-k3s-lab"}))` to see all metric names.

**Expected metric families:**

**Rocket.Chat:**
- `rocketchat_*` - Application-specific metrics
- `moleculer_*` - Microservices framework metrics
- Standard Node.js metrics (process_*, nodejs_*)

**MongoDB:**
- `mongodb_*` - Database performance metrics
- Bitnami MongoDB Exporter v0.39.0 metrics

**NATS:**
- `gnatsd_*` or `nats_*` - Messaging system metrics
- NATS Prometheus Exporter v0.9.1 metrics

### Query Patterns

**✅ Working patterns:**
```promql
# Aggregated queries
sum by (job) (up{cluster="rocketchat-k3s-lab"})
sum by (job,instance) (up{cluster="rocketchat-k3s-lab"})
rate(some_metric{cluster="rocketchat-k3s-lab"}[5m])

# Count and topk
count by (job) (up)
topk(10, some_metric{cluster="rocketchat-k3s-lab"})
```

**❌ Patterns that may not work:**
```promql
# Direct instance queries (labels may be dropped)
up{instance="10.42.0.50:9100"}

# Namespace queries (label may be renamed/dropped)
up{namespace="rocketchat"}

# Direct metric names without aggregation (may be inconsistent)
rocketchat_info
```

**💡 Best Practice:** Always use the `cluster` label and aggregation functions.

---

## 🚨 Troubleshooting Quick Reference

### No Metrics in Grafana Cloud

1. **Check time range** - Set to "Last 15 minutes"
2. **Use cluster label** - `{cluster="rocketchat-k3s-lab"}`
3. **Use aggregation** - `sum by (job) (up{...})`
4. **Check topk** - `topk(50, count by (__name__) ({cluster="rocketchat-k3s-lab"}))`

### HTTP 429 Rate Limit Errors

```bash
# Check for 429 errors
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=5m | grep "429"

# If present, verify writeRelabelConfigs
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  cat /etc/prometheus/config_out/prometheus.env.yaml 2>/dev/null \
  | grep -A 5 "write_relabel_configs"

# Check ingestion rate
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_in_total"
```

### ServiceMonitors Not Being Discovered

```bash
# Verify ServiceMonitors exist
kubectl get servicemonitor -n rocketchat

# Check service labels match ServiceMonitor selectors
kubectl get svc -n rocketchat --show-labels

# Verify Prometheus Operator is watching the rocketchat namespace
kubectl logs -n monitoring deployment/monitoring-kube-prometheus-operator \
  | grep -i "rocketchat"
```

### Duplicate Scrape Pools

```bash
# Check for duplicates
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep -o '"scrapePool":"[^"]*"' | sort | uniq -c

# Remove prometheus.io annotations if duplicates found
kubectl -n rocketchat annotate svc --all prometheus.io/scrape- prometheus.io/port- prometheus.io/path-
kubectl -n rocketchat annotate deploy --all prometheus.io/scrape- prometheus.io/port- prometheus.io/path-
kubectl -n rocketchat annotate sts --all prometheus.io/scrape- prometheus.io/port- prometheus.io/path-
```

---

## 📚 Related Documentation

- **[Troubleshooting Guide](troubleshooting.md)** - Issue #19: Grafana Cloud Rate Limiting
- **[Observability Roadmap](observability-roadmap.md)** - Future: Logs + Traces
- **[Deployment Guide](deployment.md)** - Complete deployment instructions

---

## 🎯 Success Criteria

✅ **Monitoring is working correctly if:**

1. No 429 errors in Prometheus logs for 5+ minutes
2. `prometheus_remote_storage_samples_failed_total` = 0
3. `kubectl get servicemonitor -A` shows only 4 rocketchat ServiceMonitors
4. Grafana Cloud query `sum by (job) (up{cluster="rocketchat-k3s-lab"})` returns 3 jobs (rocketchat, mongodb, nats) with value 1
5. `topk(50, count by (__name__) ({cluster="rocketchat-k3s-lab"}))` shows Rocket.Chat, MongoDB, and NATS metrics

---

**Last Updated:** October 10, 2025  
**Configuration Version:** Final (Revision 7)  
**Status:** ✅ Production Ready for Grafana Cloud Free Tier

