# Observability Verification Checklist

This document provides verification steps to confirm metrics and traces are flowing from the AKS cluster (`aks-canepro`) to the central observability hub (`observability.canepro.me`).

## Prerequisites

- `kubectl` configured to access AKS cluster
- `bash` (for running the verification script)
- Access to Grafana at `observability.canepro.me` (or appropriate dashboard)
- Basic understanding of PromQL queries

## Quick Verification Script

**Option 1: Run the automated verification script**
```bash
# From project root
bash ops/scripts/verify-observability.sh
```

**Note**: On Windows, use `bash verify-observability.sh` instead of `./verify-observability.sh` due to shebang handling.

This script checks:
- ✅ Prometheus Agent pod status and health
- ✅ OTel Collector pod status and health  
- ✅ Configuration correctness (cluster labels)
- ✅ Secret existence
- ✅ Error logs (remote_write and trace export)

## Configuration Summary

### Prometheus Agent
- **Remote Write URL**: `https://observability.canepro.me/api/v1/write`
- **Cluster Label**: `cluster=aks-canepro`
- **Namespace**: `monitoring`
- **External Labels**: `cluster`, `tenant_id`, `environment`, `workspace`, `domain`

### OTel Collector
- **Export Endpoint**: `https://observability.canepro.me` (OTLP/HTTP)
- **Cluster Attribute**: `cluster=aks-canepro` (added to all traces)
- **Namespace**: `monitoring`
- **Resource Attributes**: `cluster`, `service.name`, `deployment.environment`

### Loki Query Consumers (Optional)
- **Base URL**: `https://observability.canepro.me`
- **Query Endpoint**: `/loki/api/v1/query_range`
- **Auth**: Basic Auth via `observability-credentials`
- **Use Case**: server-side readers (for example Rocket.Chat Logs Viewer app)

---

## Step 1: Verify Prometheus Agent Status

### Check Pod Status

```bash
kubectl get pods -n monitoring -l app=prometheus-agent
```

**Expected**: Pod should be `Running` and `READY 1/1`

### Check Pod Logs for Remote Write Errors

```bash
kubectl logs -n monitoring -l app=prometheus-agent --tail=100 | grep -i "error\|fail\|write"
```

**Expected**: No errors related to remote_write. Look for successful writes or queue health messages.

### Check Prometheus Agent Config

```bash
kubectl get configmap -n monitoring prometheus-agent-config -o yaml
```

**Verify**:
- `external_labels.cluster` is set to `aks-canepro`
- `remote_write.url` points to `https://observability.canepro.me/api/v1/write`

---

## Step 2: Verify OTel Collector Status

### Check Pod Status

```bash
kubectl get pods -n monitoring -l app=otel-collector
```

**Expected**: Pod should be `Running` and `READY 1/1`

### Check Pod Logs for Export Errors

```bash
kubectl logs -n monitoring -l app=otel-collector --tail=100 | grep -i "error\|fail\|export"
```

**Expected**: No errors related to trace export. Look for successful batch exports.

### Check OTel Collector Config

```bash
kubectl get configmap -n monitoring otel-collector-config -o yaml
```

**Verify**:
- `processors.resource.attributes` includes `cluster: aks-canepro`
- `exporters.otlphttp/oke.endpoint` points to `https://observability.canepro.me`

---

## Step 3: Verify Metrics in Grafana/Mimir

### Query for AKS Cluster Metrics

In Grafana Explore (Prometheus datasource), run:

```promql
{cluster="aks-canepro"}
```

**Expected**: Should return time series with the `cluster=aks-canepro` label.

### Query Specific Metrics from AKS

```promql
# Kubernetes node metrics from AKS
up{cluster="aks-canepro", job="kubernetes-nodes"}

# RocketChat pod metrics from AKS
process_resident_memory_bytes{cluster="aks-canepro", namespace="rocketchat"}

# Prometheus Agent self-metrics
prometheus_remote_storage_succeeded_samples_total{cluster="aks-canepro"}
```

**Expected**: All queries should return results with `cluster=aks-canepro` label.

### Check Remote Write Success Rate

**Note**: Prometheus Agent self-metrics are scraped via a dedicated job. After the config is applied, these metrics will be available.

```promql
# Remote write success rate (should be close to 1.0)
# Note: Requires prometheus-agent scrape job to be configured
rate(prometheus_remote_storage_succeeded_samples_total{cluster="aks-canepro", job="prometheus-agent"}[5m]) / rate(prometheus_remote_storage_samples_total{cluster="aks-canepro", job="prometheus-agent"}[5m])
```

**Expected**: Success rate should be > 0.99 (99%+)

**Verification Status**: ✅ Metrics confirmed flowing (6,205 series visible with `cluster=aks-canepro`). Remote write is working successfully. Self-metrics scrape job added to enable detailed monitoring.

### Check Remote Write Queue Health

```promql
# Queue capacity utilization (should be < 1.0)
prometheus_remote_storage_queue_length{cluster="aks-canepro"} / prometheus_remote_storage_queue_capacity{cluster="aks-canepro"}
```

**Expected**: Queue utilization should be < 1.0 (queue not full)

---

## Step 4: Verify Traces in Grafana Tempo

### Generate Test Traces (Optional)

A test trace generation job exists at `ops/manifests/otel-tracegen-job.yaml`. To use it:

```bash
# Apply the trace generation job
kubectl apply -f ops/manifests/otel-tracegen-job.yaml

# Wait for it to complete (job name includes a date suffix)
kubectl get jobs -n monitoring -l app=otel-tracegen
kubectl wait --for=condition=complete -n monitoring -l app=otel-tracegen --timeout=120s

# Check logs
kubectl logs -n monitoring -l app=otel-tracegen --tail=100
```

### Query Traces in Grafana Tempo

In Grafana Explore (Tempo datasource), search for traces with:

**Search Query**:
- **Tags**: `cluster=aks-canepro`
- **Service Name**: `rocket-chat` (the collector upserts `service.name=rocket-chat`, including tracegen)

**Expected**: Traces should appear with the `cluster=aks-canepro` attribute.

### Verify Cluster Attribute in Traces

1. Open any trace from the search results
2. Check the trace attributes/span attributes
3. Look for `cluster: aks-canepro` in resource attributes

**Expected**: All traces should have `cluster=aks-canepro` in resource attributes.

---

## Step 5: Check OTel Collector Metrics

The OTel Collector exposes its own Prometheus metrics on port 8888. Verify span export counts:

```promql
# Spans exported by OTel Collector
rate(otelcol_exporter_sent_spans_total{cluster="aks-canepro"}[5m])

# Spans received by OTel Collector
rate(otelcol_receiver_accepted_spans_total{cluster="aks-canepro"}[5m])
```

**Expected**: If traces are being sent, both metrics should show values > 0.

---

## Step 6 (Optional): Verify Loki Query Endpoint for Reader Apps

Run from a workstation with hub credentials:

```bash
curl -sS -u 'observability-user:YOUR_PASSWORD_HERE' -G \
  'https://observability.canepro.me/loki/api/v1/query_range' \
  --data-urlencode 'query={job="rocketchat"}' \
  --data-urlencode 'limit=1'
```

**Expected**:
- `HTTP 200` and JSON response from Loki (result may be empty if no matching logs in range).

**Failure patterns**:
- `401`: Basic Auth mismatch.
- `404`: ingress route for Loki query path is missing at hub.

---

## Verification Checklist

- [ ] Prometheus Agent pod is `Running` and healthy
- [ ] Prometheus Agent logs show no remote_write errors
- [ ] Metrics with `cluster=aks-canepro` are visible in Grafana/Mimir
- [ ] Remote write success rate is > 99%
- [ ] Remote write queue is not full
- [ ] OTel Collector pod is `Running` and healthy
- [ ] OTel Collector logs show no export errors
- [ ] Traces with `cluster=aks-canepro` are searchable in Grafana Tempo
- [ ] Test traces (if generated) appear with correct cluster attribute
- [ ] Optional: Loki query endpoint responds with `200` for server-side reader use cases

---

## Troubleshooting

### No Metrics Appearing

1. **Check Secret**: Verify `observability-credentials` secret exists and has correct username/password
   ```bash
   kubectl get secret -n monitoring observability-credentials
   ```

2. **Check Network**: Verify pod can reach `observability.canepro.me`
   ```bash
   kubectl exec -n monitoring -it deployment/prometheus-agent -- wget -O- https://observability.canepro.me/api/v1/write
   ```

3. **Check Prometheus Agent Config**: Verify template was rendered correctly
   ```bash
   kubectl exec -n monitoring deployment/prometheus-agent -- cat /etc/prometheus/prometheus.yml
   ```

### No Traces Appearing

1. **Check OTel Collector Receivers**: Verify it's receiving traces
   ```bash
   kubectl logs -n monitoring -l app=otel-collector | grep "TracesExported\|spans"
   ```

2. **Check Endpoint**: Verify OTLP endpoint is correct
   ```bash
   kubectl exec -n monitoring -it deployment/otel-collector -- wget -O- https://observability.canepro.me/v1/traces
   ```

3. **Check Resource Attributes**: Verify cluster label is being added
   ```bash
   kubectl logs -n monitoring -l app=otel-collector | grep "cluster"
   ```

### Logs Viewer / Loki Reader Query Fails (404 or 502)

1. Verify app uses base URL only:
   - `loki_base_url=https://observability.canepro.me`
2. Validate query endpoint directly:
   ```bash
   curl -sS -u 'observability-user:YOUR_PASSWORD_HERE' -G \
     'https://observability.canepro.me/loki/api/v1/query_range' \
     --data-urlencode 'query={job="rocketchat"}' \
     --data-urlencode 'limit=1'
   ```
3. If `404`, ensure hub ingress exposes `/loki/api/v1/query` and `/loki/api/v1/query_range` and ArgoCD sync completed.

---

## Expected Timeline

After verification steps are complete:
- Metrics should appear in Grafana/Mimir within 30-60 seconds
- Traces should appear in Grafana Tempo within 1-2 minutes
- Both should be immediately queryable by `cluster=aks-canepro` label/attribute
