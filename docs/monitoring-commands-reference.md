# Monitoring Commands Reference

Quick reference for common monitoring operations and checks.

---

## 🚀 Quick Status Checks

### One-Line Health Check

```bash
# Check everything is healthy
kubectl get servicemonitor -A && \
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=5m | grep "429" || echo "✅ All healthy"
```

### ServiceMonitors

```bash
# List all ServiceMonitors
kubectl get servicemonitor -A

# Expected: Only rocketchat namespace with 4 ServiceMonitors

# Get detailed info
kubectl get servicemonitor -n rocketchat -o wide

# Describe specific ServiceMonitor
kubectl describe servicemonitor rocketchat-main -n rocketchat
```

### Prometheus Targets

```bash
# Check active scrape pools
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep -o '"scrapePool":"[^"]*"' | sort -u

# Count healthy targets
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep -c '"health":"up"'

# Check for duplicate instances
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep '"namespace":"rocketchat"' | grep -o '"instance":"[^"]*"' | sort | uniq -c
```

---

## 📝 Logs

### Prometheus Logs

```bash
# Tail logs
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -f

# Last 100 lines
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --tail=100

# Since specific time
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=5m

# Search for errors
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus \
  | grep -iE "error|failed" | tail -20

# Check for 429 rate limiting
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=10m \
  | grep "429" || echo "✅ No 429 errors"
```

### Config Reloader Logs

```bash
# Check config reload events
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c config-reloader --tail=20

# Watch for config changes
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c config-reloader -f
```

---

## 🔧 Configuration

### View Current Config

```bash
# List all job names in Prometheus config
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  cat /etc/prometheus/config_out/prometheus.env.yaml 2>/dev/null \
  | grep "job_name:" | sort -u

# View specific job config
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  cat /etc/prometheus/config_out/prometheus.env.yaml 2>/dev/null \
  | grep -A 50 "job_name: serviceMonitor/rocketchat/rocketchat-main"

# Check write_relabel_configs
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  cat /etc/prometheus/config_out/prometheus.env.yaml 2>/dev/null \
  | grep -B5 -A15 "write_relabel_configs"
```

### View Helm Values

```bash
# Current Helm values
helm get values -n monitoring monitoring

# Full Helm manifest
helm get manifest -n monitoring monitoring | less

# Helm release info
helm status -n monitoring monitoring
```

---

## 📊 Metrics & Statistics

### Remote Write Stats

```bash
# All remote write metrics
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage"

# Key metrics
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "prometheus_remote_storage_(samples_total|samples_failed_total|samples_pending)"

# Queue depth
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_pending"

# Sent batches
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_sent_batch_duration_seconds_count"
```

### Scrape Stats

```bash
# Samples scraped per target
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "scrape_samples_scraped" | grep "rocketchat"

# Scrape duration
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "scrape_duration_seconds" | grep "rocketchat"
```

---

## 🛠️ Maintenance Operations

### Update ServiceMonitor Intervals

```bash
# Change scrape interval to 2 minutes
kubectl patch servicemonitor rocketchat-main -n rocketchat --type='json' \
  -p='[{"op":"replace","path":"/spec/endpoints/0/interval","value":"2m"}]'

# Change back to 60 seconds
kubectl patch servicemonitor rocketchat-main -n rocketchat --type='json' \
  -p='[{"op":"replace","path":"/spec/endpoints/0/interval","value":"60s"}]'

# Batch update all ServiceMonitors
for sm in rocketchat-main rocketchat-microservices rocketchat-mongodb rocketchat-nats; do
  kubectl patch servicemonitor $sm -n rocketchat --type='json' \
    -p='[{"op":"replace","path":"/spec/endpoints/0/interval","value":"2m"}]'
done
```

### Restart Prometheus

```bash
# Graceful restart (Helm deployment)
kubectl rollout restart statefulset/prom-agent-monitoring-kube-prometheus-prometheus -n monitoring

# Force delete pod
kubectl delete pod prom-agent-monitoring-kube-prometheus-prometheus-0 -n monitoring

# Wait for ready
kubectl wait --for=condition=ready pod/prom-agent-monitoring-kube-prometheus-prometheus-0 -n monitoring --timeout=300s
```

### Update Grafana Cloud Credentials

```bash
# Delete old secret
kubectl delete secret grafana-cloud-credentials -n monitoring

# Create new secret
kubectl create secret generic grafana-cloud-credentials \
  --namespace monitoring \
  --from-literal=username="YOUR_INSTANCE_ID" \
  --from-literal=password="YOUR_API_KEY"

# Restart Prometheus to pick up new credentials
kubectl rollout restart statefulset/prom-agent-monitoring-kube-prometheus-prometheus -n monitoring
```

### Upgrade Monitoring Stack

```bash
# Update Helm repo
helm repo update prometheus-community

# Upgrade with existing values
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-rc-only.yaml

# Verify ServiceMonitors weren't recreated
kubectl get servicemonitor -A

# If K8s ServiceMonitors came back, delete them
kubectl -n monitoring get servicemonitors -o name \
  | grep -viE 'rocketchat|mongo|nats' \
  | xargs -r kubectl -n monitoring delete
```

---

## 🧹 Cleanup Operations

### Remove Duplicate Scraping

```bash
# Remove prometheus.io annotations from services
kubectl -n rocketchat annotate svc --all \
  prometheus.io/scrape- prometheus.io/port- prometheus.io/path-

# Remove from deployments
kubectl -n rocketchat annotate deploy --all \
  prometheus.io/scrape- prometheus.io/port- prometheus.io/path-

# Remove from statefulsets
kubectl -n rocketchat annotate sts --all \
  prometheus.io/scrape- prometheus.io/port- prometheus.io/path-

# Remove from pods (for immediate effect)
kubectl get pods -n rocketchat -o name \
  | xargs -I {} kubectl -n rocketchat annotate {} \
    prometheus.io/scrape- prometheus.io/port- prometheus.io/path-
```

### Delete High-Volume ServiceMonitors

```bash
# Delete all K8s infrastructure ServiceMonitors
kubectl delete servicemonitor -n monitoring \
  monitoring-kube-prometheus-kubelet \
  monitoring-kube-prometheus-operator \
  monitoring-kube-prometheus-prometheus \
  monitoring-kube-state-metrics \
  monitoring-prometheus-node-exporter \
  monitoring-kube-prometheus-coredns \
  monitoring-kube-prometheus-apiserver \
  monitoring-kube-prometheus-kube-controller-manager \
  monitoring-kube-prometheus-kube-etcd \
  monitoring-kube-prometheus-kube-proxy \
  monitoring-kube-prometheus-kube-scheduler \
  2>/dev/null || true

# Verify cleanup
kubectl get servicemonitor -A
```

---

## 🔍 Debugging

### Check ServiceMonitor to Service Matching

```bash
# Get ServiceMonitor selector
kubectl get servicemonitor rocketchat-main -n rocketchat -o yaml | grep -A 5 "selector:"

# Get matching services
kubectl get svc -n rocketchat --show-labels | grep "app.kubernetes.io/name=rocketchat"

# Check endpoints
kubectl get endpoints -n rocketchat rocketchat-rocketchat

# Describe endpoints for port details
kubectl describe endpoints -n rocketchat rocketchat-rocketchat
```

### Check Port Configurations

```bash
# List all services with ports
kubectl get svc -n rocketchat -o custom-columns=NAME:.metadata.name,PORTS:.spec.ports[*].port,PORT_NAMES:.spec.ports[*].name

# Check specific service ports
kubectl get svc rocketchat-rocketchat -n rocketchat -o yaml | grep -A 15 "ports:"

# Check pod ports
kubectl get pod -n rocketchat -l app.kubernetes.io/name=rocketchat \
  -o jsonpath='{.items[0].spec.containers[0].ports}' | python3 -m json.tool
```

### Test Metrics Endpoints

```bash
# Test from outside the pod
kubectl run -n rocketchat curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://rocketchat-rocketchat:9100/metrics | head -20

# Test MongoDB metrics
kubectl run -n rocketchat curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://rocketchat-mongodb-metrics:9216/metrics | head -20

# Test NATS metrics
kubectl run -n rocketchat curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://rocketchat-nats-metrics:7777/metrics | head -20
```

---

## 📈 Grafana Cloud Queries

### Working Query Patterns

```promql
# Check all services by job
sum by (job) (up{cluster="rocketchat-k3s-lab"})

# View all instances
sum by (job,instance) (up{cluster="rocketchat-k3s-lab"})

# Top metric names
topk(50, count by (__name__) ({cluster="rocketchat-k3s-lab"}))

# Count by labels
count by (job) (up)
count by (cluster) (up)

# Rate calculations
rate(some_metric{cluster="rocketchat-k3s-lab"}[5m])
```

### Common Queries

```promql
# Rocket.Chat request rate
sum(rate(rocketchat_meteor_methods_count{cluster="rocketchat-k3s-lab"}[5m])) by (method)

# MongoDB operations
sum(rate(mongodb_ss_opcounters{cluster="rocketchat-k3s-lab"}[5m])) by (type)

# NATS message throughput
sum(rate(gnatsd_varz_in_msgs{cluster="rocketchat-k3s-lab"}[5m]))
sum(rate(gnatsd_varz_out_msgs{cluster="rocketchat-k3s-lab"}[5m]))

# Moleculer requests
sum(rate(moleculer_request_total{cluster="rocketchat-k3s-lab"}[5m])) by (action)
```

---

## 🔄 Deployment Commands

### Initial Deployment

```bash
# Create namespace
kubectl create namespace monitoring

# Create Grafana Cloud secret
kubectl create secret generic grafana-cloud-credentials \
  --namespace monitoring \
  --from-literal=username="YOUR_INSTANCE_ID" \
  --from-literal=password="YOUR_API_KEY"

# Deploy via Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-rc-only.yaml

# Wait for ready
kubectl rollout status statefulset/prom-agent-monitoring-kube-prometheus-prometheus -n monitoring

# Delete unwanted ServiceMonitors (if any)
kubectl -n monitoring get servicemonitors -o name \
  | grep -viE 'rocketchat|mongo|nats' \
  | xargs -r kubectl -n monitoring delete
```

### Verification After Deployment

```bash
# Check pods
kubectl get pods -n monitoring

# Check ServiceMonitors
kubectl get servicemonitor -A

# Verify no 429 errors
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=2m \
  | grep "429" || echo "✅ No 429 errors"

# Check remote write stats
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "prometheus_remote_storage_(samples_total|samples_failed_total)"
```

---

## 🛠️ Troubleshooting Commands

### Diagnose 429 Rate Limiting

```bash
# Check for 429 errors
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus \
  | grep "429" | tail -10

# Check ingestion rate
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_in_total"

# Check what's causing high volume
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "scrape_samples_scraped" | sort -t= -k2 -n | tail -10
```

### Diagnose ServiceMonitor Not Discovered

```bash
# Check ServiceMonitor exists
kubectl get servicemonitor -n rocketchat

# Check selector matches service
kubectl get servicemonitor rocketchat-main -n rocketchat -o yaml | grep -A 5 "selector:"
kubectl get svc rocketchat-rocketchat -n rocketchat --show-labels

# Check namespace selector
kubectl get servicemonitor rocketchat-main -n rocketchat -o yaml | grep -A 3 "namespaceSelector:"

# Check Prometheus Operator logs
kubectl logs -n monitoring deployment/monitoring-kube-prometheus-operator \
  | grep -i "rocketchat" | tail -20
```

### Diagnose Target Down/404 Errors

```bash
# Check target health and errors
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep -E '(lastError|health)' | grep -v '"lastError":""'

# Check service endpoints
kubectl get endpoints -n rocketchat rocketchat-rocketchat
kubectl describe endpoints -n rocketchat rocketchat-rocketchat

# Test endpoint directly
kubectl run -n rocketchat curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://rocketchat-rocketchat:9100/metrics | head -20
```

---

## 🔄 Common Operations

### Force Config Reload

```bash
# Trigger config reload
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget --post-data="" http://localhost:9090/-/reload

# Or restart the pod
kubectl delete pod prom-agent-monitoring-kube-prometheus-prometheus-0 -n monitoring

# Wait for ready
sleep 30
kubectl get pod -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0
```

### Backup Current Configuration

```bash
# Export all ServiceMonitors
kubectl get servicemonitor -n rocketchat -o yaml > servicemonitors-backup.yaml

# Export Helm values
helm get values -n monitoring monitoring > monitoring-values-backup.yaml

# Export Prometheus config
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  cat /etc/prometheus/config_out/prometheus.env.yaml > prometheus-config-backup.yaml
```

### Clean Slate Reinstall

```bash
# 1. Uninstall Helm release
helm uninstall monitoring -n monitoring

# 2. Delete ServiceMonitors
kubectl delete servicemonitor -n rocketchat --all

# 3. Wait for cleanup
sleep 30

# 4. Reinstall
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-rc-only.yaml

# 5. Verify
kubectl get pods -n monitoring -w
```

---

## 📋 Verification Checklist

Run these commands to verify everything is working:

```bash
# ✅ ServiceMonitors exist
kubectl get servicemonitor -A
# Expected: 4 in rocketchat namespace

# ✅ All targets healthy
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
  | grep '"health":"up"' | grep 'rocketchat' | wc -l
# Expected: 4 or more

# ✅ No 429 errors
kubectl logs -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus --since=5m \
  | grep "429" || echo "✅ PASS"

# ✅ No failed samples
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_failed_total"
# Expected: = 0

# ✅ Samples being sent
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep "prometheus_remote_storage_samples_total"
# Expected: > 0 and increasing

# ✅ Only Rocket.Chat scrape pools
kubectl exec -n monitoring prom-agent-monitoring-kube-prometheus-prometheus-0 -c prometheus -- \
  cat /etc/prometheus/config_out/prometheus.env.yaml 2>/dev/null \
  | grep "job_name:" | sort -u
# Expected: Only serviceMonitor/rocketchat/* jobs

# ✅ Grafana Cloud query works
echo "Run in Grafana Cloud: sum by (job) (up{cluster=\"rocketchat-k3s-lab\"})"
echo "Expected: rocketchat=1, mongodb=1, nats=1"
```

**If all checks pass:** ✅ Monitoring is fully operational!

---

## 📚 Related Documentation

- [Monitoring Guide](monitoring.md) - Complete setup guide
- [Monitoring Final State](monitoring-final-state.md) - Current configuration details
- [Troubleshooting Guide](troubleshooting.md) - Issue #19: Rate Limiting
- [ServiceMonitor Debugging Summary](servicemonitor-debugging-summary.md) - Resolution timeline

---

**Last Updated:** October 10, 2025  
**Prometheus Version:** v3.6.0 (Agent Mode)  
**Helm Chart:** kube-prometheus-stack v77.14.0

