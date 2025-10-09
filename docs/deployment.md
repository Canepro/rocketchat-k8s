# Rocket.Chat k3s Lab Deployment Guide

## Server Environment
- **OS**: Ubuntu 20.04+ (recommended: 22.04 LTS)
- **Resources**: 4 vCPU, 8 GiB RAM, 19 GiB disk (minimum)
- **Cluster**: k3s (lightweight Kubernetes)
- **Ingress**: Traefik (k3s native)
- **Storage**: Dynamic provisioning with local-path (k3s default)
- **Monitoring**: Grafana Cloud integration
- **DNS**: `k8.canepro.me` → Server IP

## Prerequisites
- **k3s cluster** installed and running
- **kubectl** access configured
- **Helm v3** installed (`curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`)
- **DNS record** pointing to server IP
- **Grafana Cloud account** (free tier available)
- **Email address** for Let's Encrypt certificates
- **Storage directories** created (or use k3s dynamic provisioning)

---

## Deployment Steps

### 1. Verify k3s and Prerequisites

**Check k3s installation:**
```bash
kubectl get nodes
kubectl cluster-info
```

**Verify Traefik ingress (k3s default):**
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
kubectl get svc -n kube-system traefik
```

**Check available storage:**
```bash
df -h /
# Ensure at least 10GB free for dynamic volumes

kubectl get storageclass
# Should show: local-path (default)
```

### 2. Get Repository and Setup Grafana Cloud

**Clone repository:**
```bash
git clone https://github.com/Canepro/rocketchat-k8s.git
cd rocketchat-k8s
```

**Configure Grafana Cloud credentials:**
```bash
# Copy template and edit with your credentials
cp grafana-cloud-secret.yaml.template grafana-cloud-secret.yaml
nano grafana-cloud-secret.yaml

# Add your Grafana Cloud:
# username: "your-instance-id"     # Usually a number
# password: "your-api-key"         # Starts with glc_
```
```

**Mount the partitions:**
```bash
sudo mount /dev/nvme1n1p1 /mnt/mongo-data
sudo mount /dev/nvme2n1p1 /mnt/prometheus-data
# Optional: if using a dedicated volume for uploads
# sudo mount /dev/nvme3n1p1 /mnt/rocketchat-uploads
```

**Verify mounts:**
```bash
df -h | grep /mnt
```

**Persist across reboots:**

Get UUIDs:
```bash
sudo blkid
```

Edit `/etc/fstab` and add:
```
UUID=<mongo-uuid>      /mnt/mongo-data      ext4 defaults,nofail 0 2
UUID=<prometheus-uuid> /mnt/prometheus-data ext4 defaults,nofail 0 2
UUID=<uploads-uuid>    /mnt/rocketchat-uploads ext4 defaults,nofail 0 2
```

Replace `<mongo-uuid>` and `<prometheus-uuid>` with actual UUIDs from `blkid` output.

Apply and test:
```bash
sudo mount -a
df -h | grep /mnt
```

**Set permissions for Kubernetes:**
```bash
sudo chmod 755 /mnt/mongo-data
sudo chmod 755 /mnt/prometheus-data
sudo chmod 755 /mnt/rocketchat-uploads
```

> **Note**: If you skip this step, MongoDB, Rocket.Chat uploads, and Prometheus will fall back to default K3s storage locations.

---

### 2. Bootstrap Kubernetes with K3s
```bash
curl -sfL https://get.k3s.io | sh -
```

Verify installation:
```bash
kubectl get nodes
```

Set kubeconfig for non-root access:
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown -R $(id -u):$(id -g) ~/.kube
sudo chmod 700 ~/.kube
sudo chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config

# Make it permanent
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

Test kubectl access:
```bash
kubectl get nodes
# Should show your node in Ready state
```

---

### 3. Install Helm
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verify:
```bash
helm version
```

---

### 4. Create Persistent Volumes (If Using Dedicated Disks)

If you mounted dedicated disks in step 1, create PersistentVolumes:

**Create `persistent-volumes.yaml`:**
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mongo-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /mnt/mongo-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - <your-node-name>  # Get with: kubectl get nodes

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /mnt/prometheus-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - <your-node-name>  # Get with: kubectl get nodes

---
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
          - <your-node-name>  # Get with: kubectl get nodes
```

**Get your node name:**
```bash
kubectl get nodes
```

**Update the node name in the YAML, then apply:**
```bash
kubectl apply -f persistent-volumes.yaml
```

**Verify:**
```bash
kubectl get pv
```

**Create PersistentVolumeClaims:**

Apply the PVCs for MongoDB and Rocket.Chat uploads:
```bash
kubectl apply -f mongo-pvc.yaml
kubectl apply -f rocketchat-uploads-pvc.yaml
```

Verify the PVCs are bound:
```bash
kubectl get pvc -n rocketchat
kubectl get pv
```

You should see `mongo-pvc` bound to `mongo-pv` and `rocketchat-uploads` bound to `rocketchat-uploads-pv`.

> **Note**: The `values.yaml` references `existingClaim: mongo-pvc` for the bundled MongoDB chart and `existingClaim: rocketchat-uploads` for Rocket.Chat file uploads.

---

### 5. Deploy Ingress Controller (NGINX)
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

Wait for ingress controller to be ready:
```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

---

### 6. Deploy Cert-Manager
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
```

Wait for cert-manager to be ready:
```bash
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s
```

---

### 7. Configure Let's Encrypt ClusterIssuer
Edit `clusterissuer.yaml` and update the email address:
```yaml
email: your-email@canepro.me
```

Apply the configuration:
```bash
kubectl apply -f clusterissuer.yaml
```

Verify:
```bash
kubectl get clusterissuer
```

---

### 8. Create Monitoring Namespace
```bash
kubectl create namespace monitoring
```

---

### 9. Configure Prometheus Agent for Grafana Cloud

**Get Grafana Cloud credentials:**
1. Log in to Grafana Cloud
2. Navigate to: Connections → Add new connection → Hosted Prometheus metrics
3. Copy your Instance ID and create an API key

**Create Grafana Cloud credentials secret:**
Edit `grafana-cloud-credentials.yaml` and replace:
- `<GRAFANA_INSTANCE_ID>` → Your Grafana Cloud instance ID
- `<GRAFANA_API_KEY>` → Your Grafana Cloud API key

```bash
kubectl apply -f grafana-cloud-credentials.yaml
```

**Deploy Prometheus CRDs (for PodMonitor support):**
```bash
kubectl apply -f podmonitor-crd.yaml
```

Verify CRDs:
```bash
kubectl get crd | grep monitoring.coreos.com
```

**Deploy Prometheus Agent:**
```bash
kubectl apply -f prometheus-agent.yaml
```

Verify deployment:
```bash
kubectl get pods -n monitoring
kubectl logs -n monitoring deployment/prometheus-agent
```

Check resource usage:
```bash
kubectl top pod -n monitoring
```

> **Note**: The Prometheus agent (v3.0.0) is configured with:
> - Secret-based authentication for Grafana Cloud credentials
> - Optimized resource limits (256Mi-512Mi RAM, 100m-250m CPU) suitable for the 7.7 GB VM
> - Ephemeral storage (`emptyDir`) since agent mode forwards metrics immediately to Grafana Cloud
> - Support for PodMonitor CRDs (Rocket.Chat chart creates PodMonitors automatically)

---

### 10. Deploy Rocket.Chat via Helm

Add Rocket.Chat Helm repository:
```bash
helm repo add rocketchat https://rocketchat.github.io/helm-charts
helm repo update
```

**Create SMTP secret** (recommended for production):
```bash
kubectl create secret generic smtp-credentials \
  --from-literal=password='your-smtp-password'
```

> **Note**: The `values.yaml` is pre-configured with:
> - **Enterprise features**: Microservices mode with NATS clustering
> - **MongoDB**: Bound to `mongo-pvc` (your dedicated disk at `/mnt/mongo-data`)
> - **SMTP**: Configured via official chart block with secret injection
> - **Prometheus**: Scraping enabled on ports 9100 (main) and 9458 (microservices)
> - **PodMonitor**: Enabled (ServiceMonitor deprecated) - automatically creates PodMonitor resources
> - **Health probes**: Optimized readiness/liveness checks
> - **High availability**: 2 replicas with pod disruption budget

**Deploy Rocket.Chat:**
```bash
helm install rocketchat -f values.yaml rocketchat/rocketchat
```

Monitor deployment:
```bash
kubectl get pods -w
```

You should see pods for:
- `rocketchat-*` (2 replicas)
- `rocketchat-mongodb-*` (1 replica with metrics)
- `rocketchat-nats-*` (2 replicas for microservices communication)

Verify all components:
```bash
kubectl get pods
kubectl get svc
```

---

### 11. Verify MongoDB Metrics

MongoDB metrics are now built-in via the Bitnami chart configuration:
```bash
# Check MongoDB metrics pod
kubectl get pods -l app.kubernetes.io/name=mongodb

# MongoDB metrics are exposed internally
# Prometheus will auto-discover them via service annotations
```

> **Note**: The separate `mongodb-exporter.yaml` is no longer needed since MongoDB metrics are enabled in the Helm chart via `mongodb.metrics.enabled: true`.

---

### 12. Verify Deployment

Check all pods are running:
```bash
kubectl get pods
```

Check ingress:
```bash
kubectl get ingress
```

Check certificate:
```bash
kubectl get certificate
kubectl describe certificate rocketchat-tls
```

**Check storage usage:**
```bash
df -h | grep /mnt  # If using dedicated disks
kubectl get pvc
kubectl get pv
```

---

### 13. Access Rocket.Chat

Wait for the certificate to be issued (may take 2-5 minutes):
```bash
kubectl get certificate rocketchat-tls -w
```

Once ready, access Rocket.Chat at:
```
https://k8.canepro.me
```

---

## Post-Deployment Configuration

### Setup Rocket.Chat Admin
1. Navigate to `https://k8.canepro.me`
2. Complete the setup wizard
3. Create admin account
4. Configure SMTP settings (if not done via environment variables)

### Verify Observability
1. Log in to Grafana Cloud
2. Navigate to Explore
3. Select Prometheus datasource
4. Query: `up{job="kubernetes-pods"}`
5. You should see metrics from Rocket.Chat and MongoDB

---

## Upgrade Rocket.Chat

Update `values.yaml` with new configuration, then:
```bash
helm upgrade rocketchat -f values.yaml rocketchat/rocketchat
```

---

## Uninstall

Remove Rocket.Chat:
```bash
helm delete rocketchat
```

Remove persistent data:
```bash
kubectl delete pvc -l app.kubernetes.io/name=rocketchat
kubectl delete pvc -l app.kubernetes.io/name=mongodb
```

---

## Notes

- **TLS Certificate**: Automatically issued by Let's Encrypt via cert-manager
- **Enterprise Mode**: Microservices enabled with NATS clustering (2 replicas each)
- **MongoDB**: 
  - Deployed as ReplicaSet with persistent storage on `/mnt/mongo-data`
  - Built-in metrics exporter enabled
  - GridFS used for file uploads (no separate persistence volume needed)
- **Metrics**: 
  - Rocket.Chat main: port 9100
  - Microservices: port 9458
  - MongoDB: built-in exporter
  - NATS: exporter enabled with pod monitors
- **SMTP**: Configured via official Helm chart block with Kubernetes Secret
- **Prometheus Agent**: 
  - Version 3.0.0 with agent mode enabled
  - Secret-based Grafana Cloud authentication
  - Optimized for low resource usage (256Mi-512Mi RAM) with ephemeral storage
  - Supports PodMonitor CRDs for automatic metrics discovery
- **Resource Allocation**: Configuration tuned for 7.7 GB RAM / 2 vCPU VM
- **High Availability**: 
  - 2 Rocket.Chat replicas with minAvailable: 1
  - Pod disruption budget enabled
  - Health probes configured

For troubleshooting, see [troubleshooting.md](troubleshooting.md)

