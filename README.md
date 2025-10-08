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
        A[NGINX Ingress] -->|TLS termination| B[cert-manager]
        B -->|Let's Encrypt| C[k8.canepro.me]
    end
    
    subgraph "Application Layer"
        D[Rocket.Chat Pod 1] -.->|NATS| E[NATS Cluster]
        F[Rocket.Chat Pod 2] -.->|NATS| E
        D -->|MongoDB| G[MongoDB ReplicaSet]
        F -->|MongoDB| G
    end
    
    subgraph "Storage Layer"
        G -->|Data| H[mongo-pv<br/>2Gi]
        D -->|Uploads| I[uploads-pv<br/>5Gi]
        F -->|Uploads| I
    end
    
    subgraph "Observability"
        J[Prometheus Agent] -->|Scrape| D
        J -->|Scrape| F
        J -->|Scrape| G
        J -->|Remote Write| K[Grafana Cloud]
    end
    
    A -->|Route traffic| D
    A -->|Route traffic| F
    
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
| **Ingress** | NGINX | Latest | Load balancing & routing |
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

### Option 3: Manual Deployment

Follow the comprehensive [Deployment Guide](docs/deployment.md) for manual step-by-step instructions.

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
- **Helm** v3.0+
- **kubectl** configured with cluster access
- **DNS** record pointing to your server IP
- **Grafana Cloud** account (free tier available)

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

### Current Stack (Phase 1)

```
Rocket.Chat → Prometheus Agent → Grafana Cloud
```

**Metrics Collected:**
- 📈 Application metrics (requests, errors, latency)
- 💾 MongoDB performance (queries, connections, cache)
- 🔄 NATS messaging (throughput, queues)
- ☸️ Kubernetes cluster (pods, nodes, resources)

**Pre-built Dashboards:**
- [Rocket.Chat Metrics](https://grafana.com/grafana/dashboards/23428)
- [Microservice Metrics](https://grafana.com/grafana/dashboards/23427)
- [MongoDB Global](https://grafana.com/grafana/dashboards/23712)

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
- 🎬 **Quick Start** (above) - Fast-track deployment in 10 minutes

### Operations

- 📊 **[Observability Guide](docs/observability.md)** - Setting up monitoring and dashboards
- 🔮 **[Observability Roadmap](docs/observability-roadmap.md)** - Future: Logs + Traces with Grafana Alloy
- 🔧 **[Troubleshooting Guide](docs/troubleshooting.md)** - Common issues and solutions

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

- ✅ **Production Ready** - Actively used in production environments
- 📈 **Actively Maintained** - Regular updates and improvements
- 📚 **Well Documented** - Comprehensive guides and troubleshooting
- 🔒 **Security Focused** - Best practices for secrets and TLS

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
