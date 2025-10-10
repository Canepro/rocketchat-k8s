<div align="center">

# 🚀 Rocket.Chat on Kubernetes

**Production-ready Rocket.Chat deployment with enterprise features, automated TLS, and full observability**

[![Rocket.Chat](https://img.shields.io/badge/Rocket.Chat-v7.10.0-red?logo=rocketchat)](https://rocket.chat)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-K3s-326CE5?logo=kubernetes)](https://k3s.io)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Features](#-features) • [Quick Start](#-quick-start) • [Architecture](#-architecture) • [Documentation](#-documentation) • [Observability](#-observability)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [Prerequisites](#-prerequisites)
- [Deployment Options](#-deployment-options)
- [Storage Architecture](#-storage-architecture)
- [Observability](#-observability)
- [Configuration](#-configuration)
- [Maintenance](#-maintenance)
- [Documentation](#-documentation)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🌟 Overview

This repository provides a complete, production-ready deployment of Rocket.Chat on Kubernetes with:

- **Enterprise microservices architecture** for scalability
- **Automated TLS certificates** via Let's Encrypt
- **Comprehensive monitoring** with Grafana Cloud integration
- **Persistent storage** for database and file uploads
- **High availability** with 2+ replicas and pod disruption budgets

Perfect for teams looking to self-host Rocket.Chat with enterprise-grade reliability.

---

## ✨ Features

<table>
<tr>
<td width="50%">

### 🏢 **Enterprise Edition**
- Microservices mode enabled
- NATS clustering for message queue
- Horizontal pod autoscaling ready

### 🔒 **Security & TLS**
- Automatic Let's Encrypt certificates
- cert-manager integration
- Secret management for credentials

### 💾 **Persistent Storage**
- Dedicated volumes for MongoDB
- File upload persistence
- Backup-friendly architecture

</td>
<td width="50%">

### 📊 **Observability**
- Prometheus Agent v3.0.0
- Grafana Cloud integration
- Pre-built dashboards included
- Future: Logs + Traces via Alloy

### ⚡ **High Availability**
- 2 Rocket.Chat replicas
- MongoDB ReplicaSet
- Pod disruption budgets
- Health checks configured

### 🔧 **Production Ready**
- SMTP configuration
- Resource limits optimized
- Comprehensive documentation
- Automated deployment scripts

</td>
</tr>
</table>

---

## 🏗️ Architecture

```mermaid
graph TB
    subgraph "Ingress Layer"
        A[Traefik Ingress] -->|TLS termination| B[cert-manager]
        B -->|Let's Encrypt| C[k8.canepro.me]
    end
    
    subgraph "Application Layer"
        D[Rocket.Chat Pod] -.->|NATS| E[NATS Cluster]
        D -->|MongoDB| G[MongoDB ReplicaSet]
    end
    
    subgraph "Storage Layer"
        G -->|Data| H[mongo-pv<br/>2Gi]
        D -->|Uploads| I[uploads-pv<br/>2Gi]
    end
    
    subgraph "Observability"
        J[Prometheus Agent] -->|Scrape| D
        J -->|Scrape| G
        J -->|Remote Write| K[Grafana Cloud]
    end
    
    A -->|Route traffic| D
    
    style C fill:#f9f,stroke:#333
    style K fill:#ff9,stroke:#333
```

### Technology Stack

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Orchestration** | K3s (Kubernetes) | v1.33+ | Lightweight cluster management |
| **Application** | Rocket.Chat | v7.10.0 | Team collaboration platform |
| **Database** | MongoDB ReplicaSet | 5.0+ | Primary data store |
| **Message Queue** | NATS | 2.4+ | Microservices communication |
| **Ingress** | Traefik | Latest | Load balancing & routing |
| **TLS** | cert-manager | v1.14+ | Certificate automation |
| **Monitoring** | Prometheus Agent | v3.0.0 | Metrics collection |
| **Observability** | Grafana Cloud | - | Metrics visualization |

---

## 🚀 Quick Start

### Option 1: Automated Deployment (Recommended)

```bash
# 1. Clone the repository
git clone https://github.com/Canepro/rocketchat-k8s.git
cd rocketchat-k8s

# 2. Setup Grafana Cloud credentials
nano grafana-cloud-secret.yaml
# Add your Grafana Cloud credentials

# 3. Run the deployment script
./deploy-rocketchat.sh

# 4. Wait for certificate issuance (~5 minutes)
kubectl get certificate -n rocketchat -w

# 5. Access your Rocket.Chat instance
# https://k8.canepro.me
```

### Option 2: Interactive Deployment

```bash
# Use the interactive script for step-by-step deployment
./deploy.sh
```

### Option 3: K3s Lab Deployment (Resource-Optimized)

Perfect for testing and small team deployments on constrained resources:

```bash
# 1. Clone the repository
git clone https://github.com/Canepro/rocketchat-k8s.git
cd rocketchat-k8s

# 2. Setup Grafana Cloud credentials
cp grafana-cloud-secret.yaml.template grafana-cloud-secret.yaml
nano grafana-cloud-secret.yaml
# Add your Grafana Cloud username and API key

# 3. Apply the secret
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f grafana-cloud-secret.yaml

# 4. Deploy cert-manager and ClusterIssuer
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
kubectl wait --for=condition=Available --timeout=300s -n cert-manager deployment/cert-manager
kubectl apply -f clusterissuer.yaml

# 5. Deploy Rocket.Chat with Helm
helm repo add rocketchat https://rocketchat.github.io/helm-charts
helm repo update

helm upgrade --install rocketchat rocketchat/rocketchat \
  --namespace rocketchat --create-namespace \
  -f values.yaml

# 6. Deploy monitoring (optional)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f values-monitoring.yaml

# 7. Wait for certificate and check status
kubectl get certificate -n rocketchat -w
kubectl get pods -n rocketchat
```

**Lab Configuration Features:**
- ✅ Single replica for lower resource usage
- ✅ Traefik ingress (k3s default)
- ✅ 2Gi storage for both MongoDB and uploads
- ✅ Grafana Cloud integration (no local Grafana)
- ✅ Enterprise microservices enabled
- ✅ Automatic TLS certificates

### Option 4: Manual Deployment

Follow the comprehensive [Deployment Guide](docs/deployment.md) for manual step-by-step instructions.

---

## 🔄 Git Workflow for Lab Deployment

### From Development to Lab Server

Since you're working in VS Code with GitHub integration, here's the complete workflow:

#### 1. **Commit and Push Changes (VS Code/Local)**

```bash
# In VS Code terminal or your local machine
git add .
git commit -m "feat: Update for k3s lab deployment with Traefik and Grafana Cloud"
git push origin main
```

#### 2. **Pull Changes on Lab Server**

```bash
# SSH to your lab server
ssh cloud_user@b0f08dc8212c.mylabserver.com

# Clone (first time) or pull (updates)
# First time:
git clone https://github.com/Canepro/rocketchat-k8s.git
cd rocketchat-k8s

# For updates:
cd rocketchat-k8s
git pull origin main
```

#### 3. **Setup Grafana Cloud Credentials**

```bash
# Copy the template and add your credentials
cp grafana-cloud-secret.yaml.template grafana-cloud-secret.yaml
nano grafana-cloud-secret.yaml

# Add your actual Grafana Cloud credentials:
# username: "12345"  # Your Grafana Cloud User/Instance ID
# password: "glc_..."  # Your Grafana Cloud API Key
```

#### 4. **Deploy with Updated Configuration**

```bash
# Make deployment script executable
chmod +x deploy-rocketchat.sh

# Run the deployment
./deploy-rocketchat.sh
```

#### 5. **Monitor Deployment Progress**

```bash
# Watch pods come online
kubectl get pods -n rocketchat -w

# Check certificate status (takes 2-5 minutes)
kubectl get certificate -n rocketchat -w

# Check Grafana Cloud connectivity (if monitoring enabled)
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus | grep -i "remote_write"
```

### Updating Your Deployment

When you make configuration changes in VS Code:

```bash
# Local (VS Code)
git add .
git commit -m "Update configuration for XYZ"
git push origin main

# Lab server
git pull origin main
helm upgrade rocketchat rocketchat/rocketchat -n rocketchat -f values.yaml

# If monitoring config changed
helm upgrade monitoring prometheus-community/kube-prometheus-stack -n monitoring -f values-monitoring.yaml
```

---

## 📦 Prerequisites

### Server Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **OS** | Ubuntu 18.04+ | Ubuntu 22.04 LTS |
| **CPU** | 2 vCPUs | 4 vCPUs |
| **RAM** | 7.7 GB | 16 GB |
| **Disk (Root)** | 8 GB | 20 GB |
| **Disk (MongoDB)** | 2 GB | 10+ GB (dedicated) |
| **Disk (Uploads)** | 5 GB | 20+ GB (dedicated) |

### Software Prerequisites

- **K3s** or any Kubernetes distribution (v1.20+)
- **Helm** v3.0+ (install: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`)
- **kubectl** configured with cluster access
- **DNS** record pointing to your server IP
- **Grafana Cloud** account (free tier available)

**Quick Setup:**
```bash
# Install Helm if not present
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Create storage directories (optional for k3s with local-path)
sudo mkdir -p /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads
sudo chmod 755 /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads

# Create namespaces
kubectl create namespace rocketchat
kubectl create namespace monitoring
```

### Network Requirements

- **Port 80** (HTTP) - Let's Encrypt challenge
- **Port 443** (HTTPS) - Application access
- **Port 6443** (Optional) - Kubernetes API

---

## 🎯 Deployment Options

### Quick Deployment (10 minutes)

Best for: Testing, development, small teams

```bash
./deploy-rocketchat.sh
```

**What it does:**
- ✅ Creates all storage resources
- ✅ Deploys monitoring stack
- ✅ Installs ingress + cert-manager
- ✅ Deploys Rocket.Chat with 2 replicas
- ⏱️ Total time: ~10-15 minutes

### Custom Deployment

Best for: Production environments requiring specific configuration

1. Review and customize `values.yaml`
2. Configure storage in `persistent-volumes.yaml`
3. Update domain in `clusterissuer.yaml`
4. Follow [Deployment Guide](docs/deployment.md)

Use the [Deployment Checklist](docs/deployment-checklist.md) to ensure all steps are completed.

---

## 💾 Storage Architecture

### Three-Tier Storage Design

<table>
<tr>
<th>Component</th>
<th>Storage Type</th>
<th>Size</th>
<th>Purpose</th>
</tr>
<tr>
<td><strong>MongoDB</strong></td>
<td>Dedicated disk<br/>(or root filesystem)</td>
<td>2 Gi</td>
<td>Messages, users, rooms<br/>Chat history, metadata</td>
</tr>
<tr>
<td><strong>Uploads</strong></td>
<td>Dedicated disk<br/>(or root filesystem)</td>
<td>5 Gi</td>
<td>File attachments<br/>Avatar images, documents</td>
</tr>
<tr>
<td><strong>Prometheus</strong></td>
<td>Ephemeral<br/>(emptyDir)</td>
<td>-</td>
<td>Temporary metrics buffer<br/>Forwarded immediately</td>
</tr>
</table>

### Upload Persistence Flow

```
User Upload → Rocket.Chat Pod → PVC → PV → /mnt/rocketchat-uploads
```

**Three components required:**

1. **PersistentVolume (PV)** - Defines storage location on node
2. **PersistentVolumeClaim (PVC)** - Requests storage capacity
3. **Helm values** - Mounts PVC into pod

<details>
<summary><b>📖 Click to see detailed configuration</b></summary>

#### 1. PersistentVolume
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
                - your-node-name
```

#### 2. PersistentVolumeClaim
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

#### 3. Helm Values
```yaml
persistence:
  enabled: true
  existingClaim: rocketchat-uploads
```

</details>

---

## 📊 Observability

### Current Stack (Phase 1) - Grafana Cloud Free Tier Optimized

```
Rocket.Chat Pods → 4 ServiceMonitors → Prometheus Agent v3.0.0 → Grafana Cloud
   (9100, 9458)      (60s interval)     (write filter)        (metrics storage)
   MongoDB (9216)
   NATS (7777)
```

**Status:** ✅ Operational - No rate limiting, all targets healthy

**Metrics Collected:**
- 📈 **Rocket.Chat** - Application performance (HTTP requests, errors, latency) - port 9100
- ⚙️ **Microservices** - Moleculer framework metrics (DDP, auth, presence) - port 9458
- 💾 **MongoDB** - Database performance (queries, connections, cache, opcounters) - port 9216
- 🔄 **NATS** - Messaging throughput (connections, in/out messages, subscriptions) - port 7777

**What's NOT monitored** (to stay under free tier 1,500 samples/s limit):
- ❌ Kubernetes infrastructure (kubelet, cAdvisor, kube-state-metrics, node-exporter)
- ❌ Control plane (apiserver, scheduler, controller-manager, etcd)

**Key Stats:**
- **Ingestion Rate:** ~200-400 samples/s (73% under limit)
- **Resource Usage:** 128-256Mi RAM
- **Scrape Targets:** 4-5 active endpoints
- **Failed Samples:** 0

**Configuration Files:**
- [values-rc-only.yaml](values-rc-only.yaml) - Production Helm values
- [docs/monitoring-final-state.md](docs/monitoring-final-state.md) - Complete configuration reference

**Pre-built Dashboards:**
- [Rocket.Chat Metrics](https://grafana.com/grafana/dashboards/23428) - Dashboard ID: 23428
- [Microservice Metrics](https://grafana.com/grafana/dashboards/23427) - Dashboard ID: 23427
- [MongoDB Global](https://grafana.com/grafana/dashboards/23712) - Dashboard ID: 23712

---

### Monitoring Deployment Options

We provide **two ways** to deploy Prometheus monitoring with Grafana Cloud:

#### **Option 1: Raw Manifests (Recommended for Lab)**

Deploy Prometheus Agent v3.0.0 directly with kubectl:

```bash
# 1. Create Grafana Cloud secret
kubectl create secret generic grafana-cloud-credentials \
  --namespace monitoring \
  --from-literal=username="YOUR_GRAFANA_CLOUD_INSTANCE_ID" \
  --from-literal=password="YOUR_GRAFANA_CLOUD_API_KEY"

# 2. Deploy Prometheus Agent
kubectl apply -f manifests/

# 3. Deploy Rocket.Chat ServiceMonitors (after Rocket.Chat is running)
kubectl apply -f manifests/rocketchat-servicemonitors.yaml

# 4. Verify deployment
kubectl get pods -n monitoring
kubectl get servicemonitor -n rocketchat
kubectl logs -n monitoring -l app=prometheus-agent
```

**Pros:**
- ✅ Simple and lightweight (~256-512Mi RAM)
- ✅ No Helm Operator overhead
- ✅ Fast deployment (~1 minute)
- ✅ Easy to customize scrape configs

**Configuration Files:**
- `manifests/prometheus-agent-configmap.yaml` - Scrape configs and remote write
- `manifests/prometheus-agent-deployment.yaml` - Prometheus Agent deployment
- `manifests/prometheus-agent-rbac.yaml` - ServiceAccount and permissions

See [manifests/README.md](manifests/README.md) for detailed instructions.

#### **Option 2: Helm Chart (Production)**

Deploy kube-prometheus-stack via Helm:

```bash
# 1. Create Grafana Cloud secret (same as above)
kubectl create secret generic grafana-cloud-credentials \
  --namespace monitoring \
  --from-literal=username="YOUR_GRAFANA_CLOUD_INSTANCE_ID" \
  --from-literal=password="YOUR_GRAFANA_CLOUD_API_KEY"

# 2. Add Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 3. Deploy monitoring stack
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f values-monitoring.yaml

# 4. Verify deployment
kubectl get pods -n monitoring
```

**Pros:**
- ✅ Full Prometheus Operator stack
- ✅ Includes kube-state-metrics and node-exporter
- ✅ ServiceMonitor/PodMonitor support
- ✅ Easy upgrades via Helm

**Configuration File:**
- `values-monitoring.yaml` - Helm chart values

**Note**: This deploys additional components (kube-state-metrics, node-exporter), requiring more resources (~1-2Gi total RAM).

### Setting Up Grafana Cloud

#### 1. Create Grafana Cloud Account

1. Go to [Grafana Cloud](https://grafana.com/products/cloud/)
2. Sign up for a free account (includes 10k metrics, 50GB logs, 50GB traces)
3. Create your first stack (e.g., "rocketchat-lab")

#### 2. Get Your Credentials

1. In your Grafana Cloud dashboard, click "Details" next to **Prometheus**
2. Copy the **Remote Write Endpoint**
3. Copy your **Username/Instance ID** (usually a numeric ID)
4. Generate or copy your **Password/API Key**

#### 3. Create Kubernetes Secret

```bash
# Create the secret directly
kubectl create secret generic grafana-cloud-credentials \
  --namespace monitoring \
  --from-literal=username="YOUR_INSTANCE_ID" \
  --from-literal=password="YOUR_API_KEY"

# OR use the template file
cp grafana-cloud-secret.yaml.template grafana-cloud-secret.yaml
nano grafana-cloud-secret.yaml  # Edit with your credentials
kubectl apply -f grafana-cloud-secret.yaml
```

#### 4. Update Remote Write Endpoint

If your Grafana Cloud region differs, update the endpoint URL:

**For Raw Manifests:**
Edit `manifests/prometheus-agent-configmap.yaml`:
```yaml
remote_write:
  - url: https://prometheus-prod-XX-prod-REGION.grafana.net/api/prom/push
```

**For Helm:**
Edit `values-monitoring.yaml`:
```yaml
remoteWrite:
  - url: https://prometheus-prod-XX-prod-REGION.grafana.net/api/prom/push
```

#### 5. Deploy Monitoring

Choose your deployment method (see [Monitoring Deployment Options](#monitoring-deployment-options) above).

#### 6. Import Dashboards

Once metrics start flowing (2-5 minutes), import the Rocket.Chat dashboards:

1. In Grafana Cloud, go to **Dashboards** → **New** → **Import**
2. Enter dashboard ID: `23428` (Rocket.Chat Metrics)
3. Select your Prometheus data source
4. Click **Import**
5. Repeat for dashboard IDs: `23427` (Microservices), `23712` (MongoDB)

**Automated Import:**
Use the provided script to import all dashboards at once:
```bash
export GRAFANA_URL="https://YOUR_STACK.grafana.net"
export GRAFANA_API_KEY="YOUR_API_KEY"
export GRAFANA_DATASOURCE="Prometheus"

./scripts/import-grafana-dashboards.sh
```

### Future: Full Observability (Phase 2+)

Upgrade to **Grafana Alloy** for unified observability:

- 📊 **Metrics** - Current functionality (already have)
- 📝 **Logs** - Application & system log aggregation
- 🔍 **Traces** - End-to-end request tracing
- 🔗 **Correlation** - Jump from metric → log → trace

See [Observability Roadmap](docs/observability-roadmap.md) for migration guide.

---

## ⚙️ Configuration

### Core Configuration Files

<table>
<tr>
<th width="30%">File</th>
<th width="70%">Description</th>
</tr>
<tr>
<td><code>values.yaml</code></td>
<td>Helm chart values - Rocket.Chat configuration, replicas, resources, persistence</td>
</tr>
<tr>
<td><code>clusterissuer.yaml</code></td>
<td>Let's Encrypt issuer - Email, ACME server, challenge method</td>
</tr>
<tr>
<td><code>persistent-volumes.yaml</code></td>
<td>PersistentVolumes - Storage definitions for MongoDB, uploads, Prometheus</td>
</tr>
<tr>
<td><code>mongo-pvc.yaml</code></td>
<td>MongoDB PVC - Claims storage for database data</td>
</tr>
<tr>
<td><code>rocketchat-uploads-pvc.yaml</code></td>
<td>Uploads PVC - Claims storage for file attachments</td>
</tr>
</table>

### Monitoring & Observability

<table>
<tr>
<th width="30%">File</th>
<th width="70%">Description</th>
</tr>
<tr>
<td><code>prometheus-agent.yaml</code></td>
<td>Prometheus Agent v3.0.0 deployment with remote write to Grafana Cloud</td>
</tr>
<tr>
<td><code>grafana-cloud-secret.yaml</code></td>
<td>Grafana Cloud credentials (⚠️ not in git, create from template)</td>
</tr>
<tr>
<td><code>podmonitor-crd.yaml</code></td>
<td>Minimal CRDs for Rocket.Chat chart PodMonitor support</td>
</tr>
</table>

### Deployment Scripts

| Script | Use Case |
|--------|----------|
| `deploy-rocketchat.sh` | **Automated** - One-command deployment |
| `deploy.sh` | **Interactive** - Step-by-step with confirmations |
| `scripts/import-grafana-dashboards.sh` | Import pre-built Grafana dashboards |

---

## 🔧 Maintenance

### Common Operations

```bash
# View logs
kubectl logs -l app.kubernetes.io/name=rocketchat -f

# Check pod status
kubectl get pods -n rocketchat

# Check certificate status
kubectl get certificate -n rocketchat

# Restart Rocket.Chat
kubectl rollout restart deployment rocketchat -n rocketchat

# Upgrade to new version
helm upgrade rocketchat -f values.yaml rocketchat/rocketchat -n rocketchat
```

### Backup & Restore

#### Backup MongoDB
```bash
# Create backup
kubectl exec -n rocketchat rocketchat-mongodb-0 -- \
  mongodump --uri="mongodb://root:rocketchatroot@localhost:27017" \
  --out=/tmp/backup

# Copy backup to local machine
kubectl cp rocketchat/rocketchat-mongodb-0:/tmp/backup ./mongodb-backup-$(date +%Y%m%d)
```

#### Backup File Uploads
```bash
# Copy uploads directory from node
ssh user@your-node
sudo tar -czf rocketchat-uploads-$(date +%Y%m%d).tar.gz /mnt/rocketchat-uploads/
```

### Monitoring Health

```bash
# Check resource usage
kubectl top pods -n rocketchat

# View recent events
kubectl get events -n rocketchat --sort-by='.lastTimestamp'

# Check persistent volumes
kubectl get pv,pvc -n rocketchat
```

---

## 📚 Documentation

### Getting Started

- 🚀 **[Deployment Guide](docs/deployment.md)** - Complete step-by-step deployment instructions
- ✅ **[Deployment Checklist](docs/deployment-checklist.md)** - Verification steps for each phase
- 📝 **[Deployment Summary](docs/deployment-summary.md)** - Real-world deployment timeline and lessons learned
- 🎬 **Quick Start** (above) - Fast-track deployment in 10 minutes

### Operations

- 📊 **[Monitoring Guide](docs/monitoring.md)** - Complete monitoring setup with Grafana Cloud
- ✅ **[Monitoring Final State](docs/monitoring-final-state.md)** - Current production configuration (Grafana Cloud Free Tier optimized)
- 🔮 **[Observability Roadmap](docs/observability-roadmap.md)** - Future: Logs + Traces with Grafana Alloy
- 🔧 **[Troubleshooting Guide](docs/troubleshooting.md)** - Common issues and solutions (19 documented issues)

### Reference

- ⚙️ **Configuration** - See [Configuration](#-configuration) section above
- 💾 **Storage** - See [Storage Architecture](#-storage-architecture) section above
- 🏗️ **Architecture** - See [Architecture](#-architecture) section above

---

## 🆘 Troubleshooting

### Quick Diagnostic Commands

```bash
# Check if all pods are running
kubectl get pods -n rocketchat

# View pod logs
kubectl logs -n rocketchat <pod-name>

# Describe problematic resource
kubectl describe pod -n rocketchat <pod-name>

# Check ingress configuration
kubectl get ingress -n rocketchat -o yaml
```

### Common Issues

| Issue | Quick Fix | Documentation |
|-------|-----------|---------------|
| **Pods CrashLooping** | Check logs: `kubectl logs <pod>` | [Troubleshooting #1](docs/troubleshooting.md#issue-1-pods-in-crashloopbackoff) |
| **Certificate not issued** | Check DNS, ClusterIssuer | [Troubleshooting #2](docs/troubleshooting.md#issue-2-tls-certificate-not-issued) |
| **Can't access Rocket.Chat** | Check ingress, service, firewall | [Troubleshooting #3](docs/troubleshooting.md#issue-3-ingress-not-working) |
| **Kubectl permission denied** | Fix kubeconfig permissions | [Troubleshooting #0](docs/troubleshooting.md#issue-0-kubectl-permission-denied) |
| **PVC not binding** | Check storage directories exist | [Troubleshooting #9](docs/troubleshooting.md#issue-9-persistentvolume-not-binding) |

For comprehensive troubleshooting, see the **[Troubleshooting Guide](docs/troubleshooting.md)**.

---

## 🤝 Contributing

Contributions are welcome! Whether it's:

- 🐛 Bug fixes
- ✨ New features
- 📝 Documentation improvements
- 💡 Suggestions and ideas

Please feel free to open an issue or submit a pull request.

### Development Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📊 Project Status

- ✅ **Production Ready** - Successfully deployed and tested (October 2025)
- 📈 **Actively Maintained** - Regular updates and improvements
- 📚 **Well Documented** - Comprehensive guides with real deployment experience
- 🔒 **Security Focused** - Best practices for secrets and TLS
- 🎯 **Battle-Tested** - Complete deployment documented in [deployment-summary.md](docs/deployment-summary.md)

### Recent Deployment Success

**Lab Environment (October 9, 2025):**
- ✅ k3s v1.33.5 cluster
- ✅ 13 pods running (9 Rocket.Chat + 4 Monitoring)
- ✅ TLS certificate issued (Let's Encrypt)
- ✅ Grafana Cloud metrics flowing
- ✅ Total deployment: ~30 minutes
- ✅ Resource usage: ~5Gi / 8Gi RAM

See [docs/deployment-summary.md](docs/deployment-summary.md) for complete timeline and lessons learned.

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [Rocket.Chat](https://rocket.chat) - The amazing team collaboration platform
- [K3s](https://k3s.io) - Lightweight Kubernetes distribution
- [cert-manager](https://cert-manager.io) - Automated certificate management
- [Grafana Labs](https://grafana.com) - Observability platform

---

## 📞 Support & Contact

- 📖 **Documentation**: See [docs/](docs/) directory
- 🐛 **Issues**: [GitHub Issues](https://github.com/Canepro/rocketchat-k8s/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/Canepro/rocketchat-k8s/discussions)

---

<div align="center">

**⭐ Star this repository if it helped you!**

Made with ❤️ for the Kubernetes community

[Report Bug](https://github.com/Canepro/rocketchat-k8s/issues) • [Request Feature](https://github.com/Canepro/rocketchat-k8s/issues) • [Documentation](docs/)

</div>
