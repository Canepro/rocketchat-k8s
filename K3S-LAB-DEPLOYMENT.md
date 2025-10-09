# 🚀 k3s Lab Deployment - Quick Reference

## What Was Updated

This repository has been optimized for deployment on a **k3s lab server** with the following changes:

### ✅ **Configuration Changes**

| File | What Changed | Why |
|------|--------------|-----|
| `values.yaml` | • `replicaCount: 1` (was 2)<br/>• `ingressClassName: traefik`<br/>• Added proper ingress hosts<br/>• Storage: 2Gi (was mixed sizes) | Resource optimization for lab server |
| `clusterissuer.yaml` | • `class: traefik` (was nginx) | k3s uses Traefik by default |
| `deploy-rocketchat.sh` | • Removed NGINX setup<br/>• Added Traefik verification<br/>• Added monitoring deployment | Updated for k3s + Grafana Cloud |

### 📦 **New Files**

| File | Purpose |
|------|---------|
| `values-monitoring.yaml` | Prometheus Agent → Grafana Cloud configuration |
| `grafana-cloud-secret.yaml.template` | Template for Grafana Cloud credentials |
| `.gitignore` | Already exists, includes grafana-cloud-secret.yaml |

---

## 🎯 **Deployment Workflow**

### From VS Code to Lab Server

```bash
# 1. In VS Code (commit changes)
git add .
git commit -m "Update for k3s lab deployment"
git push origin main

# 2. On lab server (get updates)
ssh cloud_user@b0f08dc8212c.mylabserver.com
git clone https://github.com/Canepro/rocketchat-k8s.git  # First time
cd rocketchat-k8s
git pull origin main  # For updates

# 3. Setup credentials
cp grafana-cloud-secret.yaml.template grafana-cloud-secret.yaml
nano grafana-cloud-secret.yaml  # Add your Grafana Cloud credentials

# 4. Deploy
chmod +x deploy-rocketchat.sh
./deploy-rocketchat.sh
```

---

## 📊 **Architecture Overview**

### Lab Configuration
- **Replicas**: 1 (instead of 2) to fit resource constraints
- **Storage**: 2Gi volumes (MongoDB + Uploads) via k3s local-path
- **Ingress**: Traefik (k3s native) instead of NGINX
- **Monitoring**: Prometheus Agent → Grafana Cloud (no local Grafana)
- **Features**: Full Enterprise Edition with microservices + NATS

### Resource Usage
```
CPU: ~1.5 cores (Rocket.Chat + MongoDB + NATS)
RAM: ~3-4 GiB (within 8GiB server limit)
Storage: ~4-6 GiB (2Gi MongoDB + 2Gi uploads + k3s overhead)
```

---

## 🔗 **Key URLs and Resources**

| Resource | URL/Command |
|----------|-------------|
| **Application** | https://k8.canepro.me |
| **Repository** | https://github.com/Canepro/rocketchat-k8s |
| **Grafana Cloud** | https://grafana.com/products/cloud/ |
| **Dashboards** | IDs: 23428, 23427, 23712 |

### Monitoring Queries
```promql
# Check if metrics are flowing
up{cluster="rocketchat-k3s-lab"}

# Rocket.Chat status
rocketchat_up{cluster="rocketchat-k3s-lab"}

# MongoDB metrics
mongodb_up{cluster="rocketchat-k3s-lab"}
```

---

## 🛠️ **Troubleshooting**

### Common Issues
```bash
# Check pod status
kubectl get pods -n rocketchat
kubectl get pods -n monitoring

# Check certificate (takes 2-5 minutes)
kubectl describe certificate rocketchat-tls -n rocketchat

# Check Grafana Cloud connectivity
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus | grep remote_write

# Check ingress
kubectl get ingress -n rocketchat
kubectl describe ingress rocketchat -n rocketchat
```

### Update Deployment
```bash
# Update Rocket.Chat config
git pull origin main
helm upgrade rocketchat rocketchat/rocketchat -n rocketchat -f values.yaml

# Update monitoring
helm upgrade monitoring prometheus-community/kube-prometheus-stack -n monitoring -f values-monitoring.yaml
```

---

## 🎉 **Success Criteria**

- [ ] All pods running in `rocketchat` namespace
- [ ] Certificate issued and ready
- [ ] https://k8.canepro.me accessible
- [ ] Grafana Cloud receiving metrics
- [ ] Admin user created in Rocket.Chat
- [ ] Dashboards imported in Grafana Cloud

**Total deployment time: ~10-15 minutes**