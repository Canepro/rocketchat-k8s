# Observability Quick Reference

**Last Updated:** December 1, 2025

## 🚀 Quick Links

| Service | URL | Purpose |
|---------|-----|---------|
| **Grafana** | https://observability.canepro.me | Dashboards & Explore |
| **Prometheus** | https://observability.canepro.me/prometheus | Metrics queries |
| **Loki** | https://observability.canepro.me/loki | Log queries (via Grafana) |
| **Tempo** | https://observability.canepro.me/tempo | Trace queries (via Grafana) |

## 📊 Common Queries

### Prometheus (Metrics)

```promql
# HTTP request rate
rate(rocketchat_http_requests_total[5m])

# Memory usage by pod
container_memory_usage_bytes{namespace="rocketchat"}

# CPU usage by pod
rate(container_cpu_usage_seconds_total{namespace="rocketchat"}[5m])

# Pod restart count
kube_pod_container_status_restarts_total{namespace="rocketchat"}

# Active connections
rocketchat_websocket_connections

# Message send rate
rate(rocketchat_messages_sent_total[5m])
```

### Loki (Logs)

```logql
# All Rocket.Chat logs
{namespace="rocketchat"}

# Error logs only
{namespace="rocketchat"} |= "error" or "Error" or "ERROR"

# Specific pod
{namespace="rocketchat", pod=~"rocketchat-rocketchat-.*"}

# OTLP connection logs
{namespace="rocketchat"} |= "OTLP" or "OpenTelemetry"

# Last 5 minutes of errors
{namespace="rocketchat"} |= "error" [5m]

# Count errors per minute
sum(count_over_time({namespace="rocketchat"} |= "error" [1m]))
```

### Tempo (Traces)

```
# All traces from Rocket.Chat
{service.name="rocket-chat"}

# Slow requests (>1 second)
{duration>1s}

# Failed requests
{status=error}

# Specific operation
{service.name="rocket-chat" && name="http.request"}
```

## 🔧 Common Operations

### Check Agent Status

```bash
# View Grafana Agent pods
kubectl get pods -n monitoring

# Check agent logs
kubectl logs -n monitoring deployment/grafana-agent --tail=100

# Verify OTLP receiver
kubectl logs -n monitoring deployment/grafana-agent | grep -i "Starting.*server"
```

### Test OTLP Endpoint

```bash
# Test from rocketchat namespace
kubectl run -i --tty --rm curl-test --image=curlimages/curl --restart=Never -n rocketchat -- \
  curl -v -X POST http://otel-collector.monitoring:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'

# Expected: HTTP/1.1 200 OK with {"partialSuccess":{}}
```

### Check Rocket.Chat Observability

```bash
# Verify OTLP connection
kubectl logs -n rocketchat deployment/rocketchat-rocketchat --tail=50 | grep -i otlp

# Check for connection errors
kubectl logs -n rocketchat deployment/rocketchat-rocketchat --tail=200 | grep -i econnrefused

# View all Rocket.Chat pods
kubectl get pods -n rocketchat -l app.kubernetes.io/name=rocketchat
```

### Restart Components

```bash
# Restart Grafana Agent
kubectl rollout restart deployment/grafana-agent -n monitoring

# Restart Rocket.Chat (to reconnect OTLP)
kubectl rollout restart deployment/rocketchat-rocketchat -n rocketchat

# Wait for rollout
kubectl rollout status deployment/rocketchat-rocketchat -n rocketchat
```

## 🐛 Troubleshooting

### OTLP Connection Refused

**Symptoms:**
- `ECONNREFUSED 10.0.10.119:4318` in Rocket.Chat logs
- No traces appearing in Tempo

**Fix:**
```bash
# 1. Verify agent is running
kubectl get pods -n monitoring

# 2. Check OTLP receiver started
kubectl logs -n monitoring deployment/grafana-agent | grep -i "Starting.*server"

# 3. Test endpoint
kubectl run -i --tty --rm curl-test --image=alpine --restart=Never -n rocketchat -- \
  /bin/sh -c "nc -zvw2 otel-collector.monitoring 4318"

# 4. Restart Rocket.Chat
kubectl rollout restart deployment/rocketchat-rocketchat -n rocketchat
```

### Logs Not Appearing

**Check log tailers:**
```bash
kubectl logs -n monitoring deployment/grafana-agent | grep "tailer running"
```

**Verify pod labels:**
```bash
kubectl get pods -n rocketchat --show-labels | grep rocketchat
```

### Metrics Not Updating

**Check scraping:**
```bash
kubectl logs -n monitoring deployment/grafana-agent | grep "prometheus.scrape"
```

**Verify Prometheus endpoint:**
```bash
kubectl port-forward -n rocketchat deployment/rocketchat-rocketchat 9458:9458
curl http://localhost:9458/metrics
```

## 📝 Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `k8s-agent-values.yaml` | Grafana Agent Helm values | Repository root |
| `values.yaml` | Rocket.Chat Helm values | Repository root |
| `OBSERVABILITY-CURRENT-STATE.md` | Full documentation | `docs/` |

## 🔐 Credentials

**Central Observability Stack:**
- Username: `observability-user`
- Password: `50JjX+diU6YmAZPl`
- Stored in: `k8s-agent-values.yaml`

## 📈 Service Endpoints

**otel-collector Service:**
- Namespace: `monitoring`
- ClusterIP: `10.0.10.119`
- OTLP gRPC: `4317`
- OTLP HTTP: `4318`

**grafana-agent Service:**
- Namespace: `monitoring`
- HTTP: `80`
- OTLP gRPC: `4317`
- OTLP HTTP: `4318`

## 🎯 Health Indicators

✅ **Healthy State:**
- Grafana Agent pod is Running
- OTLP receiver logs show "Starting HTTP server" and "Starting GRPC server"
- Rocket.Chat logs show OTLP endpoint without ECONNREFUSED errors
- Test curl returns HTTP 200
- Logs show "tailer running" for all Rocket.Chat pods

❌ **Unhealthy State:**
- ECONNREFUSED errors in Rocket.Chat logs
- No "tailer running" messages in agent logs
- Test curl fails or times out
- Agent pod is not Running

## 📚 Additional Resources

- [Full Documentation](OBSERVABILITY-CURRENT-STATE.md)
- [Setup Guide](../external-config/ROCKETCHAT-SETUP.md)
- [Grafana Agent Docs](https://grafana.com/docs/agent/latest/)
- [OpenTelemetry Docs](https://opentelemetry.io/docs/)

---

**Quick Start:** Access https://observability.canepro.me → Explore → Select datasource (Prometheus/Loki/Tempo) → Run queries above

