# Rocket.Chat Kubernetes Deployment Checklist

## Environment Details
- **Cluster**: k3s v1.33.5+k3s1
- **Node**: `b0f08dc8212c.mylabserver.com`
- **Helm**: v3.19.0
- **Domain**: `k8.canepro.me`
- **Storage**: 
  - `/mnt/mongo-data` (2 GiB)
  - `/mnt/prometheus-data` (2 GiB)
  - `/mnt/rocketchat-uploads` (5 GiB)

---

## Pre-Deployment Verification

### ✅ Kubectl Access Setup

**If you're a non-root user and get permission denied errors:**
```bash
# Setup kubectl access
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

### ✅ Cluster Status
```bash
kubectl get nodes
# Expected: b0f08dc8212c.mylabserver.com Ready

kubectl cluster-info
kubectl version --short
```

### ✅ Storage Mounts
```bash
df -h | grep /mnt
# Expected (minimum):
# /dev/nvme1n1p1  2.0G   /mnt/mongo-data
# /dev/nvme2n1p1  2.0G   /mnt/prometheus-data

# Check all directories exist
ls -ld /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads
# All three directories should exist, even if uploads is not on dedicated disk

# Verify they're accessible
sudo chmod 755 /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads
```

**Note**: `/mnt/rocketchat-uploads` can be on root filesystem (no dedicated disk needed). This is a valid configuration.

### ✅ Namespaces
```bash
kubectl get namespaces
# Expected: monitoring, rocketchat
```

---

## Deployment Steps

### Step 1: Deploy Storage (PV + PVC)

```bash
# Apply PersistentVolumes
kubectl apply -f persistent-volumes.yaml

# Verify PVs are Available
kubectl get pv
# Expected: mongo-pv (2Gi), prometheus-pv (2Gi) - Status: Available

# Apply MongoDB PVC
kubectl apply -f mongo-pvc.yaml

# Verify PVC is Bound
kubectl get pvc -n rocketchat
# Expected: mongo-pvc - Status: Bound to mongo-pv

# Detailed check
kubectl describe pv mongo-pv
kubectl describe pvc mongo-pvc -n rocketchat
```

**Before applying PVs, ensure directories exist:**
```bash
# Create directories if they don't exist
sudo mkdir -p /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads
sudo chmod 755 /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads
```

**✅ Success Criteria:**
- [ ] All mount directories exist (`/mnt/mongo-data`, `/mnt/prometheus-data`, `/mnt/rocketchat-uploads`)
- [ ] PVs created with correct paths and node affinity
- [ ] mongo-pvc and rocketchat-uploads PVC bound to respective PVs
- [ ] No events showing binding issues

---

### Step 2: Install NGINX Ingress Controller

```bash
# Deploy ingress-nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# Wait for controller to be ready (2-3 minutes)
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Verify
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

**✅ Success Criteria:**
- [ ] ingress-nginx-controller pod Running
- [ ] Service has LoadBalancer or NodePort configured

---

### Step 3: Install cert-manager

```bash
# Deploy cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml

# Wait for cert-manager to be ready (2-3 minutes)
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=300s

# Verify
kubectl get pods -n cert-manager
```

**✅ Success Criteria:**
- [ ] cert-manager pod Running
- [ ] cert-manager-webhook pod Running
- [ ] cert-manager-cainjector pod Running

---

### Step 4: Configure Let's Encrypt ClusterIssuer

```bash
# Verify email is set in clusterissuer.yaml
grep -A 2 "email:" clusterissuer.yaml

# Apply ClusterIssuer
kubectl apply -f clusterissuer.yaml

# Verify ClusterIssuer is ready
kubectl get clusterissuer
kubectl describe clusterissuer production-cert-issuer
```

**✅ Success Criteria:**
- [ ] ClusterIssuer status: Ready
- [ ] ACME account registered

---

### Step 5: Deploy Prometheus Agent

**Create Grafana Cloud credentials secret:**

```bash
# Edit grafana-cloud-credentials.yaml
nano grafana-cloud-credentials.yaml
# Replace <GRAFANA_INSTANCE_ID> and <GRAFANA_API_KEY>

# Apply the secret
kubectl apply -f grafana-cloud-credentials.yaml

# Verify secret is created
kubectl get secret -n monitoring grafana-cloud-credentials
kubectl describe secret -n monitoring grafana-cloud-credentials
```

**Deploy PodMonitor CRDs:**

```bash
# Apply minimal CRDs for Rocket.Chat chart compatibility
kubectl apply -f podmonitor-crd.yaml

# Verify CRDs are installed
kubectl get crd | grep monitoring.coreos.com
# Expected: podmonitors.monitoring.coreos.com, servicemonitors.monitoring.coreos.com
```

**Deploy Prometheus Agent:**

```bash
# Apply Prometheus Agent (v3.0.0 with secret-based auth)
kubectl apply -f prometheus-agent.yaml

# Verify deployment
kubectl get pods -n monitoring
kubectl logs -n monitoring deployment/prometheus-agent

# Check resource usage
kubectl top pod -n monitoring
```

**✅ Success Criteria:**
- [ ] grafana-cloud-credentials secret created
- [ ] PodMonitor and ServiceMonitor CRDs installed
- [ ] prometheus-agent pod Running (using Prometheus v3.0.0)
- [ ] No connection/authentication errors in logs
- [ ] Memory usage under 512Mi
- [ ] Metrics appearing in Grafana Cloud

---

### Step 6: Create Rocket.Chat Namespace

```bash
# Create namespace
kubectl create namespace rocketchat

# Verify namespace
kubectl get namespace rocketchat
```

### Step 7: Prepare SMTP Secret

```bash
# Create SMTP password secret
kubectl create secret generic smtp-credentials -n rocketchat \
  --from-literal=password='YOUR_MAILGUN_PASSWORD'

# Verify secret exists
kubectl get secret smtp-credentials -n rocketchat
kubectl describe secret smtp-credentials -n rocketchat
```

**✅ Success Criteria:**
- [ ] rocketchat namespace created
- [ ] Secret created in rocketchat namespace
- [ ] Contains 'password' key

---

### Step 8: Add Rocket.Chat Helm Repository

```bash
# Add Helm repo
helm repo add rocketchat https://rocketchat.github.io/helm-charts

# Update repos
helm repo update

# Search for chart
helm search repo rocketchat

# View chart values (optional)
helm show values rocketchat/rocketchat > default-values.yaml
```

**✅ Success Criteria:**
- [ ] Helm repo added successfully
- [ ] Chart found and up to date

---

### Step 9: Deploy Rocket.Chat

**Pre-deployment verification:**

```bash
# Verify all prerequisites
kubectl get pvc -n rocketchat        # mongo-pvc: Bound, rocketchat-uploads: Bound
kubectl get clusterissuer            # production-cert-issuer: Ready
kubectl get secret -n rocketchat     # smtp-credentials exists
kubectl get pods -n monitoring       # prometheus-agent: Running

# DNS check
nslookup k8.canepro.me
# Should resolve to your server IP
```

**Deploy:**

```bash
# Install Rocket.Chat
helm install rocketchat -f values.yaml rocketchat/rocketchat -n rocketchat

# Watch deployment progress
kubectl get pods -n rocketchat -w
```

**Expected pods:**
- `rocketchat-*` (2 replicas)
- `rocketchat-mongodb-*` (1 replica + metrics sidecar)
- `rocketchat-nats-*` (2 replicas)

**Monitor:**

```bash
# Check all pods
kubectl get pods -n rocketchat

# Check services
kubectl get svc -n rocketchat

# Check ingress
kubectl get ingress -n rocketchat

# Check certificate
kubectl get certificate -n rocketchat
kubectl describe certificate rocketchat-tls -n rocketchat
```

**✅ Success Criteria:**
- [ ] All Rocket.Chat pods Running (2/2)
- [ ] MongoDB pod Running (1/1)
- [ ] NATS pods Running (2/2)
- [ ] Ingress created
- [ ] Certificate issued (may take 2-5 minutes)

---

### Step 10: Verify TLS Certificate

```bash
# Watch certificate status
kubectl get certificate -n rocketchat -w

# Check certificate details
kubectl describe certificate rocketchat-tls -n rocketchat

# Check cert-manager logs if issues
kubectl logs -n cert-manager deployment/cert-manager -f

# Once ready, test HTTPS
curl -v https://k8.canepro.me
```

**✅ Success Criteria:**
- [ ] Certificate status: Ready
- [ ] Secret rocketchat-tls created
- [ ] HTTPS accessible without warnings

---

### Step 11: Access & Configure Rocket.Chat

```bash
# Check all resources are ready
kubectl get all -n rocketchat

# Port-forward for initial access (if DNS not ready)
kubectl port-forward -n rocketchat svc/rocketchat 3000:3000

# Access via browser
# - Local: http://localhost:3000
# - Public: https://k8.canepro.me
```

**Initial Setup:**
1. Open `https://k8.canepro.me`
2. Complete setup wizard
3. Create admin account
4. Configure workspace

**Verify SMTP:**
1. Go to Administration → Email → SMTP
2. Check configuration matches values.yaml
3. Send test email

**✅ Success Criteria:**
- [ ] Web UI accessible
- [ ] Admin account created
- [ ] SMTP test email received
- [ ] No errors in browser console

---

## Post-Deployment Verification

### Health Checks

```bash
# Pod health
kubectl get pods -n rocketchat
kubectl top pods -n rocketchat

# Logs
kubectl logs -n rocketchat -l app.kubernetes.io/name=rocketchat --tail=50
kubectl logs -n rocketchat -l app.kubernetes.io/name=mongodb --tail=50
kubectl logs -n rocketchat -l app.kubernetes.io/name=nats --tail=50

# Endpoints
kubectl get endpoints -n rocketchat

# Ingress
kubectl describe ingress -n rocketchat
```

### Metrics Verification

```bash
# Test Rocket.Chat metrics endpoints
kubectl run test-metrics --rm -it --image=curlimages/curl -n rocketchat -- sh
# Inside pod:
curl http://rocketchat:9100/metrics | head -20
curl http://rocketchat:9458/metrics | head -20
exit

# Check Prometheus agent is scraping
kubectl logs -n monitoring deployment/prometheus-agent | grep -i scrape

# Verify in Grafana Cloud
# Navigate to Explore → PromQL
# Query: up{cluster="rocketchat-k8s"}
```

### Storage Verification

```bash
# Check PVC usage
kubectl exec -n rocketchat rocketchat-mongodb-0 -- df -h /bitnami/mongodb

# Host disk usage
df -h /mnt/mongo-data
df -h /mnt/prometheus-data
df -h /mnt/rocketchat-uploads
```

**✅ Success Criteria:**
- [ ] All pods healthy
- [ ] Metrics flowing to Grafana Cloud
- [ ] MongoDB storing data on dedicated disk
- [ ] No error logs

---

## Troubleshooting Quick Reference

### Pods not starting
```bash
kubectl describe pod <pod-name> -n rocketchat
kubectl logs <pod-name> -n rocketchat
kubectl get events -n rocketchat --sort-by='.lastTimestamp'
```

### Certificate issues
```bash
kubectl describe certificate rocketchat-tls -n rocketchat
kubectl logs -n cert-manager deployment/cert-manager
kubectl get certificaterequest -n rocketchat
```

### MongoDB connection issues
```bash
kubectl logs -n rocketchat -l app.kubernetes.io/name=rocketchat | grep -i mongo
kubectl exec -n rocketchat rocketchat-mongodb-0 -- mongosh --eval "db.adminCommand('ping')"
```

### NATS issues
```bash
kubectl logs -n rocketchat -l app.kubernetes.io/name=nats
kubectl exec -n rocketchat <rocketchat-pod> -- nc -zv rocketchat-nats 4222
```

### Ingress not working
```bash
kubectl describe ingress -n rocketchat
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
curl -v http://k8.canepro.me
```

---

## Rollback Procedure

If deployment fails:

```bash
# Uninstall Helm release
helm uninstall rocketchat -n rocketchat

# Delete PVCs (only if you want to start fresh)
kubectl delete pvc mongo-pvc -n rocketchat

# Clean up secrets
kubectl delete secret smtp-credentials -n rocketchat

# Review and fix issues, then redeploy
```

---

## Maintenance Commands

### View Helm release
```bash
helm list -n rocketchat
helm status rocketchat -n rocketchat
helm get values rocketchat -n rocketchat
```

### Upgrade configuration
```bash
# Edit values.yaml, then:
helm upgrade rocketchat -f values.yaml rocketchat/rocketchat -n rocketchat
```

### Restart components
```bash
kubectl rollout restart deployment rocketchat -n rocketchat
kubectl rollout restart statefulset rocketchat-mongodb -n rocketchat
kubectl rollout restart statefulset rocketchat-nats -n rocketchat
```

### Backup MongoDB
```bash
kubectl exec -n rocketchat rocketchat-mongodb-0 -- \
  mongodump --uri="mongodb://rocketchat:rocketchat@localhost:27017/rocketchat" \
  --out=/tmp/backup

kubectl cp rocketchat/rocketchat-mongodb-0:/tmp/backup ./mongodb-backup-$(date +%Y%m%d)
```

---

## Success Checklist

- [ ] All PVs and PVCs bound correctly
- [ ] NGINX Ingress Controller running
- [ ] cert-manager operational
- [ ] ClusterIssuer ready
- [ ] Grafana Cloud credentials secret created
- [ ] PodMonitor/ServiceMonitor CRDs installed
- [ ] Prometheus agent (v3.0.0) sending metrics to Grafana Cloud
- [ ] All Rocket.Chat pods running (2x app, 1x mongo, 2x nats)
- [ ] TLS certificate issued and valid
- [ ] Rocket.Chat accessible at https://k8.canepro.me
- [ ] Admin account created
- [ ] SMTP tested and working
- [ ] Metrics visible in Grafana Cloud
- [ ] MongoDB using dedicated storage (/mnt/mongo-data)
- [ ] Rocket.Chat uploads stored on /mnt/rocketchat-uploads

---

**📌 For detailed troubleshooting, see [troubleshooting.md](troubleshooting.md)**
