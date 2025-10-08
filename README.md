# Rocket.Chat Kubernetes Deployment

This repository contains configuration files and documentation for deploying Rocket.Chat on Kubernetes in microservices mode with observability via Grafana Cloud.

## Architecture

- **Kubernetes**: K3s (lightweight Kubernetes)
- **Rocket.Chat**: v7.10.0 (Enterprise microservices mode, 2 replicas)
- **Database**: MongoDB ReplicaSet with built-in metrics (persistent storage)
- **Message Queue**: NATS cluster (2 replicas for microservices communication)
- **Ingress**: NGINX Ingress Controller
- **TLS**: Let's Encrypt via cert-manager
- **Observability**: Prometheus Agent → Grafana Cloud
- **Domain**: `k8.canepro.me`

## Quick Start

```bash
# 1. Clone repository and setup credentials
git clone https://github.com/Canepro/rocketchat-k8s.git
cd rocketchat-k8s

# 2. Setup Grafana Cloud credentials
cp .gitignore.example grafana-cloud-secret.yaml
nano grafana-cloud-secret.yaml  # Add your actual credentials

# 3. Install K3s (if not already installed)
curl -sfL https://get.k3s.io | sh -

# 4. Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 5. Deploy infrastructure
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
kubectl apply -f clusterissuer.yaml

# 6. Deploy monitoring
kubectl create namespace monitoring
kubectl apply -f grafana-cloud-secret.yaml      # Created from template above
kubectl apply -f podmonitor-crd.yaml             # CRDs for Rocket.Chat chart
kubectl apply -f prometheus-agent.yaml

# 7. Setup storage (if using dedicated disks)
kubectl apply -f persistent-volumes.yaml
kubectl apply -f mongo-pvc.yaml

# 8. Deploy Rocket.Chat
helm repo add rocketchat https://rocketchat.github.io/helm-charts
helm repo update
helm install rocketchat -f values.yaml rocketchat/rocketchat

# 9. Setup Grafana dashboards (optional)
# Follow docs/observability.md for dashboard import instructions

# 10. Access Rocket.Chat
# https://k8.canepro.me
```

## Configuration Files

### Core Configuration
- **`values.yaml`** - Helm values for Rocket.Chat deployment with PodMonitor enabled
- **`clusterissuer.yaml`** - Let's Encrypt certificate issuer configuration

### Monitoring & Observability
- **`grafana-cloud-credentials.yaml`** - Grafana Cloud authentication secret (update with your credentials)
- **`prometheus-agent.yaml`** - Prometheus Agent v3.0.0 with secret-based auth
- **`podmonitor-crd.yaml`** - Minimal PodMonitor/ServiceMonitor CRDs for Rocket.Chat chart
- **`mongodb-exporter.yaml`** - Deprecated (MongoDB metrics now built into Helm chart)

### Storage
- **`persistent-volumes.yaml`** - PersistentVolume definitions for dedicated disks
- **`mongo-pvc.yaml`** - PersistentVolumeClaim for MongoDB data

### Scripts
- **`deploy.sh`** - Interactive deployment script (bash)
- **`deploy-rocketchat.sh`** - Automated Rocket.Chat deployment script
- **`scripts/import-grafana-dashboards.sh`** - Grafana dashboard import utility

## Documentation

- **[Deployment Guide](docs/deployment.md)** - Comprehensive step-by-step deployment instructions
- **[Deployment Checklist](docs/deployment-checklist.md)** - Step-by-step verification checklist
- **[Troubleshooting Guide](docs/troubleshooting.md)** - Common issues and solutions
- **[Observability Guide](docs/observability.md)** - Monitoring setup with Grafana dashboards

## Server Requirements

- **OS**: Ubuntu 18.04+
- **RAM**: 7.7 GB minimum
- **CPU**: 2 vCPUs minimum
- **Disk**: 8 GB minimum
- **Docker**: Installed
- **DNS**: Domain pointing to server IP

## Features

- ✅ **Enterprise Edition**: Microservices mode with NATS clustering
- ✅ **TLS/HTTPS**: Automatic Let's Encrypt certificates via cert-manager
- ✅ **High Availability**: 2 replicas with pod disruption budget
- ✅ **Persistent Storage**: MongoDB on dedicated disk with Rocket.Chat uploads persisted via PVC
- ✅ **Built-in Metrics**: MongoDB, NATS, and Rocket.Chat exporters
- ✅ **Optimized Monitoring**: Prometheus Agent v3.0.0 (256-512 MB) with Grafana Cloud
- ✅ **Secret-based Auth**: Secure credential management for Grafana Cloud
- ✅ **PodMonitor Support**: CRDs for metrics collection without full Prometheus Operator
- ✅ **Health Checks**: Configured liveness/readiness probes
- ✅ **SMTP**: Production-ready configuration with secret management
- ✅ **Resource Tuned**: Optimized for 7.7 GB RAM / 2 vCPU environments

## 🧩 Upload Persistence Architecture

Rocket.Chat file uploads require three components working together:

### 1. PersistentVolume (PV)

Defines the actual storage on the node. Points to `/mnt/rocketchat-uploads` via `hostPath`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: rocketchat-uploads-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /mnt/rocketchat-uploads
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - b0f08dc8212c.mylabserver.com
```

### 2. PersistentVolumeClaim (PVC)

Claims the storage capacity. The `rocketchat-uploads` PVC binds to the PV above:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rocketchat-uploads
  namespace: rocketchat
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-storage
```

### 3. Rocket.Chat Helm Configuration

Tells Rocket.Chat pods to mount the PVC at `/app/uploads` (container path):

```yaml
persistence:
  enabled: true
  existingClaim: rocketchat-uploads
```

**Result**: Files uploaded to Rocket.Chat are stored at `/mnt/rocketchat-uploads` on the node and persist across pod restarts.

## Monitoring

Metrics are collected via Prometheus Agent v3.0.0 and sent to Grafana Cloud:
- **Rocket.Chat Main**: Port 9100 (application metrics)
- **Rocket.Chat Microservices**: Port 9458 (service-specific metrics)
- **MongoDB**: Built-in Bitnami exporter (enabled in Helm chart)
- **NATS**: Exporter enabled with PodMonitors
- **Kubernetes**: Cluster, node, pod, and service metrics
- **Authentication**: Secret-based credentials for Grafana Cloud
- **Resource Usage**: Prometheus agent optimized with 256Mi-512Mi RAM limits
- **Storage**: Ephemeral storage (agent mode forwards metrics immediately)
- **CRDs**: Minimal PodMonitor/ServiceMonitor CRDs (no full Prometheus Operator needed)

## Maintenance

### Upgrade Rocket.Chat
```bash
# Update values.yaml with new configuration
helm upgrade rocketchat -f values.yaml rocketchat/rocketchat
```

### View Logs
```bash
kubectl logs -l app.kubernetes.io/name=rocketchat -f
```

### Check Status
```bash
kubectl get pods
kubectl get ingress
kubectl get certificate
```

### Backup MongoDB
```bash
kubectl exec -it rocketchat-mongodb-0 -- mongodump --uri="mongodb://root:rocketchatroot@localhost:27017" --out=/tmp/backup
kubectl cp rocketchat-mongodb-0:/tmp/backup ./mongodb-backup
```

## License

This configuration is provided as-is for deploying Rocket.Chat on Kubernetes. Licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
