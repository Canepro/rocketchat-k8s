# Prometheus Agent Raw Manifests

This directory contains raw Kubernetes manifests for deploying Prometheus Agent v3.0.0 in agent mode with Grafana Cloud remote write.

## Files

- **`prometheus-agent-configmap.yaml`** - Prometheus configuration with scrape configs and Grafana Cloud remote write
- **`prometheus-agent-deployment.yaml`** - Deployment for Prometheus Agent v3.0.0
- **`prometheus-agent-rbac.yaml`** - ServiceAccount, ClusterRole, and ClusterRoleBinding for Prometheus
- **`servicemonitor-crd.yaml`** - ServiceMonitor CRD (optional, for compatibility)

## Prerequisites

1. **Create monitoring namespace:**
   ```bash
   kubectl create namespace monitoring
   ```

2. **Create Grafana Cloud secret:**
   ```bash
   kubectl create secret generic grafana-cloud-credentials \
     --namespace monitoring \
     --from-literal=username="YOUR_GRAFANA_CLOUD_INSTANCE_ID" \
     --from-literal=password="YOUR_GRAFANA_CLOUD_API_KEY"
   ```

## Deployment

### Option 1: Deploy All at Once

```bash
kubectl apply -f manifests/
```

### Option 2: Deploy Step by Step

```bash
# 1. Create namespace
kubectl create namespace monitoring

# 2. Apply RBAC
kubectl apply -f manifests/prometheus-agent-rbac.yaml

# 3. Apply ConfigMap (after updating Grafana Cloud URL if needed)
kubectl apply -f manifests/prometheus-agent-configmap.yaml

# 4. Apply Deployment
kubectl apply -f manifests/prometheus-agent-deployment.yaml

# 5. (Optional) Apply ServiceMonitor CRD
kubectl apply -f manifests/servicemonitor-crd.yaml
```

## Verification

```bash
# Check pods
kubectl get pods -n monitoring

# Check logs
kubectl logs -n monitoring -l app=prometheus-agent

# Check remote write status
kubectl logs -n monitoring -l app=prometheus-agent | grep -i "remote_write"
```

## Configuration

### Update Grafana Cloud Endpoint

Edit `prometheus-agent-configmap.yaml` and update the remote_write URL:

```yaml
remote_write:
  - url: https://prometheus-prod-XX-prod-REGION.grafana.net/api/prom/push
```

Replace with your actual Grafana Cloud endpoint from:
1. Grafana Cloud → Prometheus → Details → "Remote Write Endpoint"

### Customize Scrape Configs

The ConfigMap includes three scrape jobs:
- **kubernetes-pods** - Scrapes pods with `prometheus.io/scrape: "true"` annotation
- **kubernetes-services** - Scrapes services with `prometheus.io/scrape: "true"` annotation
- **kubernetes-nodes** - Scrapes node metrics

## Resource Usage

**Default limits:**
- Memory: 256Mi (request) / 512Mi (limit)
- CPU: 100m (request) / 250m (limit)

Adjust in `prometheus-agent-deployment.yaml` if needed.

## Grafana Cloud Dashboards

Once metrics are flowing, import these dashboards in Grafana Cloud:
- **23428** - Rocket.Chat Metrics
- **23427** - Microservice Metrics  
- **23712** - MongoDB Global (v2)

## Uninstall

```bash
kubectl delete -f manifests/
```

Or selectively:
```bash
kubectl delete deployment prometheus-agent -n monitoring
kubectl delete configmap prometheus-agent-config -n monitoring
kubectl delete clusterrolebinding prometheus-agent
kubectl delete clusterrole prometheus-agent
kubectl delete serviceaccount prometheus-agent -n monitoring
```

## Notes

- **Agent Mode**: Prometheus runs in agent mode (no local storage, immediate remote write)
- **Ephemeral Storage**: Uses `emptyDir` for temporary WAL (Write-Ahead Log)
- **RBAC**: ClusterRole required for cluster-wide service discovery
- **Secret**: Must be named `grafana-cloud-credentials` in `monitoring` namespace

