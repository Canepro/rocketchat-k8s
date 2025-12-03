# Observability Current State

**Last Updated:** December 1, 2025  
**Status:** ✅ Fully Operational

## Architecture Overview

```
Rocket.Chat Pods (rocketchat namespace)
├─ Metrics (:9100, :9458)
├─ Logs (stdout/stderr)
└─ Traces (OpenTelemetry OTLP)
       ↓
Grafana Agent (monitoring namespace)
├─ Flow mode with River config
├─ Prometheus scraping
├─ Loki log collection
└─ OTLP trace receiver (ports 4317/4318)
       ↓
Central Observability Stack
├─ Prometheus → https://observability.canepro.me/prometheus
├─ Loki → https://observability.canepro.me/loki
└─ Tempo → https://observability.canepro.me/tempo
       ↓
Grafana Dashboard
└─ https://observability.canepro.me (or grafana.canepro.me)
```

## Current Deployment

### Grafana Agent Configuration

**File:** `k8s-agent-values.yaml`

**Key Features:**
- **Mode:** Flow (River configuration language)
- **Metrics:** Scrapes Rocket.Chat pods matching label `app.kubernetes.io/name=rocketchat.*`
- **Logs:** Collects from all Rocket.Chat pod containers via Kubernetes API
- **Traces:** OTLP receiver on ports 4317 (gRPC) and 4318 (HTTP)

**Endpoints:**
```yaml
Metrics: https://observability.canepro.me/api/v1/write
Logs:    https://observability.canepro.me/loki/api/v1/push
Traces:  https://observability.canepro.me/v1/traces
```

**Authentication:**
- Username: `observability-user`
- Password: `50JjX+diU6YmAZPl` (stored in k8s-agent-values.yaml)

### Services

**otel-collector Service:**
```yaml
Name: otel-collector
Namespace: monitoring
Type: ClusterIP
IP: 10.0.10.119
Selector: app.kubernetes.io/name=grafana-agent
Ports:
  - otlp-grpc: 4317/TCP
  - otlp-http: 4318/TCP
  - jaeger-grpc: 14250/TCP
  - jaeger-http: 14268/TCP
  - jaeger-compact: 6831/TCP
  - jaeger-binary: 6832/TCP
  - zipkin: 9411/TCP
  - prometheus: 8888/TCP
  - metrics: 8889/TCP
```

**grafana-agent Service:**
```yaml
Name: grafana-agent
Namespace: monitoring
Type: ClusterIP
Ports:
  - http: 80/TCP
  - otlp-grpc: 4317/TCP
  - otlp-http: 4318/TCP
```

### Rocket.Chat Configuration

**OTLP Environment Variables:**
```yaml
OTEL_SERVICE_NAME: rocket-chat
OTEL_SERVICE_VERSION: 7.9.3
OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector.monitoring.svc.cluster.local:4318
OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf
OTEL_TRACES_EXPORTER: otlp
OTEL_METRICS_EXPORTER: none
OTEL_LOGS_EXPORTER: none
OTEL_RESOURCE_ATTRIBUTES: service.name=rocket-chat,service.version=7.9.3,deployment.environment=production,service.namespace=rocketchat
OTEL_LOG_LEVEL: info
NODE_OPTIONS: --require /otel-auto-instrumentation/tracing.js
```

**Prometheus Metrics:**
```yaml
OVERWRITE_SETTING_Prometheus_Enabled: "true"
OVERWRITE_SETTING_Prometheus_Port: "9458"
MS_METRICS: "true"
MS_METRICS_PORT: "9459"
```

## Monitored Components

### Rocket.Chat Pods
- ✅ `rocketchat-rocketchat` - Main application
- ✅ `rocketchat-account` - Account microservice
- ✅ `rocketchat-authorization` - Authorization microservice
- ✅ `rocketchat-presence` - Presence microservice
- ✅ `rocketchat-stream-hub` - Stream hub microservice
- ✅ `rocketchat-ddp-streamer` - DDP streamer

### Infrastructure
- ✅ MongoDB (via Bitnami exporter)
- ✅ NATS (via built-in exporter)
- ✅ Kubernetes cluster metrics

## Verification Commands

### Check Grafana Agent Status
```bash
# View pods
kubectl get pods -n monitoring

# Check logs
kubectl logs -n monitoring deployment/grafana-agent --tail=100

# Verify OTLP receiver is listening
kubectl logs -n monitoring deployment/grafana-agent | grep -i "Starting.*server"
```

### Test OTLP Endpoint
```bash
# Test connectivity from rocketchat namespace
kubectl run -i --tty --rm curl-test --image=curlimages/curl --restart=Never -n rocketchat -- \
  curl -v -X POST http://otel-collector.monitoring:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'

# Expected: HTTP/1.1 200 OK with {"partialSuccess":{}}
```

### Check Rocket.Chat Logs
```bash
# Verify OTLP connection
kubectl logs -n rocketchat deployment/rocketchat-rocketchat --tail=50 | grep -i otlp

# Should show: [OpenTelemetry] OTLP Endpoint: http://otel-collector.monitoring.svc.cluster.local:4318
# Should NOT show: ECONNREFUSED errors
```

### Verify Log Collection
```bash
# Check Grafana Agent is tailing logs
kubectl logs -n monitoring deployment/grafana-agent | grep -i "loki\|rocketchat" | tail -20

# Should show: "tailer running" and "opened log stream" messages
```

## Troubleshooting

### OTLP Connection Refused

**Symptom:** `ECONNREFUSED 10.0.10.119:4318` in Rocket.Chat logs

**Solution:**
1. Verify Grafana Agent is running and OTLP receiver started:
   ```bash
   kubectl logs -n monitoring deployment/grafana-agent | grep -i "Starting.*server"
   ```

2. Test endpoint connectivity:
   ```bash
   kubectl run -i --tty --rm curl-test --image=alpine --restart=Never -n rocketchat -- \
     /bin/sh -c "nc -zvw2 otel-collector.monitoring 4318"
   ```

3. If agent is working but Rocket.Chat still shows errors, restart Rocket.Chat:
   ```bash
   kubectl rollout restart deployment/rocketchat-rocketchat -n rocketchat
   ```

### Logs Not Appearing

**Check Grafana Agent log tailers:**
```bash
kubectl logs -n monitoring deployment/grafana-agent | grep "tailer running"
```

**Verify pod labels match discovery rules:**
```bash
kubectl get pods -n rocketchat --show-labels | grep rocketchat
```

### Traces Not Showing

**Verify OTLP endpoint accepts traces:**
```bash
kubectl run -i --tty --rm curl-test --image=curlimages/curl --restart=Never -n rocketchat -- \
  curl -v -X POST http://otel-collector.monitoring:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'
```

**Check Rocket.Chat OTLP configuration:**
```bash
kubectl get deployment rocketchat-rocketchat -n rocketchat -o yaml | grep -A 5 OTEL_EXPORTER_OTLP_ENDPOINT
```

## Resource Usage

### Grafana Agent
- **Memory:** 512Mi - 1Gi
- **CPU:** 250m - 500m
- **Replicas:** 1 (Deployment)

### Network
- **Ingress:** Minimal (only scraping/polling)
- **Egress:** ~1-5 MB/min to central observability stack

## Access Points

### Dashboards
- **Grafana:** https://observability.canepro.me or https://grafana.canepro.me
- **Prometheus:** https://observability.canepro.me/prometheus
- **Loki:** https://observability.canepro.me/loki (via Grafana Explore)
- **Tempo:** https://observability.canepro.me/tempo (via Grafana Explore)

### Query Examples

**Prometheus (Metrics):**
```promql
# Request rate
rate(rocketchat_http_requests_total[5m])

# Memory usage
container_memory_usage_bytes{namespace="rocketchat"}

# Pod restarts
kube_pod_container_status_restarts_total{namespace="rocketchat"}
```

**Loki (Logs):**
```logql
# All Rocket.Chat logs
{namespace="rocketchat"}

# Error logs only
{namespace="rocketchat"} |= "error" or "Error" or "ERROR"

# Specific pod
{namespace="rocketchat", pod=~"rocketchat-rocketchat-.*"}
```

**Tempo (Traces):**
```
# Search by service
{service.name="rocket-chat"}

# Search by duration
{duration>1s}

# Search by status
{status=error}
```

## Maintenance

### Update Grafana Agent
```bash
# Update Helm repo
helm repo update grafana

# Upgrade release
helm upgrade grafana-agent grafana/grafana-agent \
  -n monitoring \
  -f k8s-agent-values.yaml
```

### Restart Grafana Agent
```bash
kubectl rollout restart deployment/grafana-agent -n monitoring
```

### View Configuration
```bash
# View current config
kubectl get configmap grafana-agent -n monitoring -o yaml

# View rendered River config
kubectl logs -n monitoring deployment/grafana-agent | grep "config.river"
```

## Known Issues

### Duplicate MS_METRICS Environment Variables
**Warning:** `spec.template.spec.containers[0].env[18]: hides previous definition of "MS_METRICS"`

**Impact:** None - Kubernetes uses the last definition
**Fix:** Clean up duplicate entries in Rocket.Chat deployment (optional)

### Old Pod References in Logs
**Warning:** `pods "rocketchat-rocketchat-5ff55d4f56-5k2cm" not found`

**Impact:** None - Expected during pod restarts
**Behavior:** Grafana Agent automatically detects new pods and starts tailing

## Success Indicators

✅ **Metrics:** Grafana Agent logs show `prometheus.scrape.rocketchat` evaluations every ~5s  
✅ **Logs:** Grafana Agent logs show `tailer running` for all Rocket.Chat pods  
✅ **Traces:** OTLP receiver shows `Starting HTTP server` and `Starting GRPC server`  
✅ **Rocket.Chat:** No `ECONNREFUSED` errors in logs  
✅ **Connectivity:** Test curl returns `HTTP/1.1 200 OK`  

## Next Steps

1. **Create Dashboards** - Build Grafana dashboards for Rocket.Chat metrics
2. **Set Up Alerts** - Configure alerting rules for critical metrics
3. **Log Analysis** - Create saved Loki queries for common troubleshooting
4. **Trace Analysis** - Identify slow requests and bottlenecks using Tempo
5. **Documentation** - Update team runbooks with observability queries

---

**Document Version:** 1.0  
**Deployment Date:** December 1, 2025  
**Status:** Production - Fully Operational

