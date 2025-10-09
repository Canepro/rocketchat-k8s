# Rocket.Chat Kubernetes Troubleshooting Guide

## Prerequisites Issues

### Issue 0: Kubectl Permission Denied

**Symptoms:**
```bash
kubectl get nodes
# Error: error loading config file "/etc/rancher/k3s/k3s.yaml": open /etc/rancher/k3s/k3s.yaml: permission denied
```

**Diagnosis:**
```bash
ls -la /etc/rancher/k3s/k3s.yaml
ls -la ~/.kube/
```

**Solutions:**

**For non-root users, setup kubectl access:**
```bash
# Create .kube directory
mkdir -p ~/.kube

# Copy k3s config to user directory
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Fix ownership
sudo chown -R $(id -u):$(id -g) ~/.kube

# Fix permissions
sudo chmod 700 ~/.kube
sudo chmod 600 ~/.kube/config

# Export KUBECONFIG
export KUBECONFIG=~/.kube/config

# Make permanent
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc

# Test
kubectl get nodes
```

**Alternative: Use sudo (not recommended for regular use):**
```bash
sudo kubectl get nodes
```

---

## General Debugging Commands

### Check Pod Status
```bash
kubectl get pods
kubectl get pods -A  # All namespaces
```

### View Pod Logs
```bash
kubectl logs <pod-name>
kubectl logs <pod-name> -f  # Follow logs
kubectl logs <pod-name> --previous  # Previous container logs
```

### Describe Resources
```bash
kubectl describe pod <pod-name>
kubectl describe ingress rocketchat
kubectl describe certificate rocketchat-tls
```

### Check Events
```bash
kubectl get events --sort-by='.lastTimestamp'
```

---

## Storage Management

### Verify Mounted Volumes
```bash
df -h | grep /mnt
lsblk
```

### Check PersistentVolumes
```bash
kubectl get pv
kubectl get pvc
kubectl describe pv <pv-name>
kubectl describe pvc <pvc-name>
```

### Check Disk Usage
```bash
# Overall disk usage
df -h

# Check all mounted volumes
df -h | grep /mnt

# MongoDB data directory
du -sh /mnt/mongo-data

# Prometheus data directory
du -sh /mnt/prometheus-data

# Rocket.Chat uploads directory
du -sh /mnt/rocketchat-uploads

# Inside MongoDB pod
kubectl exec -it rocketchat-mongodb-0 -- df -h
```

---

## Common Issues

### Issue 1: Pods in CrashLoopBackOff

**Symptoms:**
```bash
kubectl get pods
NAME                         READY   STATUS             RESTARTS   AGE
rocketchat-xyz               0/1     CrashLoopBackOff   5          5m
```

**Diagnosis:**
```bash
kubectl logs rocketchat-xyz
kubectl describe pod rocketchat-xyz
```

**Common Causes:**
- MongoDB connection issues
- Insufficient resources
- Configuration errors

**Solutions:**

Check MongoDB is running:
```bash
kubectl get pods -l app.kubernetes.io/name=mongodb
kubectl logs <mongodb-pod-name>
```

Check resource allocation:
```bash
kubectl top nodes
kubectl top pods
```

Verify environment variables:
```bash
kubectl get deployment rocketchat -o yaml | grep -A 20 env
```

---

### Issue 2: TLS Certificate Not Issued

**Symptoms:**
```bash
kubectl get certificate
NAME              READY   SECRET           AGE
rocketchat-tls    False   rocketchat-tls   5m
```

**Diagnosis:**
```bash
kubectl describe certificate rocketchat-tls
kubectl describe certificaterequest
kubectl logs -n cert-manager deployment/cert-manager
```

**Common Causes:**
- DNS not propagated
- Port 80 blocked (required for HTTP-01 challenge)
- ClusterIssuer misconfigured

**Solutions:**

Verify DNS resolution:
```bash
nslookup k8.canepro.me
dig k8.canepro.me
```

Check port 80 accessibility:
```bash
curl http://k8.canepro.me/.well-known/acme-challenge/test
```

Verify ClusterIssuer:
```bash
kubectl get clusterissuer
kubectl describe clusterissuer production-cert-issuer
```

Check cert-manager logs:
```bash
kubectl logs -n cert-manager deployment/cert-manager -f
```

Manual certificate deletion (to retry):
```bash
kubectl delete certificate rocketchat-tls
kubectl delete secret rocketchat-tls
# Cert-manager will recreate automatically
```

---

### Issue 3: Ingress Not Working

**Symptoms:**
- Cannot access Rocket.Chat at `https://k8.canepro.me`
- Connection refused or timeout errors

**Diagnosis:**
```bash
kubectl get ingress
kubectl describe ingress rocketchat
kubectl get svc -n ingress-nginx
```

**Solutions:**

Check ingress controller:
```bash
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

Verify service endpoints:
```bash
kubectl get endpoints rocketchat
```

Test internal connectivity:
```bash
kubectl run test-pod --rm -it --image=curlimages/curl -- sh
# Inside pod:
curl http://rocketchat:3000
```

Check external connectivity:
```bash
curl -v http://k8.canepro.me
curl -v https://k8.canepro.me
```

---

### Issue 4: MongoDB Connection Issues

**Symptoms:**
- Rocket.Chat pods failing with database connection errors
- Logs showing `MongoNetworkError` or similar

**Diagnosis:**
```bash
kubectl logs <rocketchat-pod> | grep -i mongo
kubectl get svc rocketchat-mongodb
```

**Solutions:**

Check MongoDB status:
```bash
kubectl get pods -l app.kubernetes.io/name=mongodb
kubectl logs <mongodb-pod-name>
```

Verify MongoDB service:
```bash
kubectl get svc rocketchat-mongodb
kubectl describe svc rocketchat-mongodb
```

Test MongoDB connectivity:
```bash
kubectl run mongodb-test --rm -it --image=mongo:5.0 -- bash
# Inside pod:
mongosh mongodb://root:rocketchatroot@rocketchat-mongodb:27017
```

Check MongoDB credentials in Helm values:
```bash
helm get values rocketchat
```

---

### Issue 5: Prometheus Agent Not Scraping Metrics

**Symptoms:**
- No Rocket.Chat metrics in Grafana Cloud
- Prometheus agent logs show scrape errors
- Agent pod restarting or showing high resource usage
- Remote write authentication errors

**Diagnosis:**
```bash
kubectl logs -n monitoring deployment/prometheus-agent
kubectl get pods -o wide | grep rocketchat
kubectl top pod -n monitoring  # Check resource usage
```

**Solutions:**

**Verify Grafana Cloud secret exists and is correct:**
```bash
# Check secret exists
kubectl get secret -n monitoring grafana-cloud-credentials

# If missing, create it
kubectl apply -f grafana-cloud-credentials.yaml

# Restart agent to pick up the secret
kubectl rollout restart deployment/prometheus-agent -n monitoring
```

**Verify pod annotations:**
```bash
kubectl get pods -o yaml | grep -A 5 annotations
```

**Test metrics endpoints:**
```bash
kubectl run test-curl --rm -it --image=curlimages/curl -- sh
# Inside pod:
curl http://<rocketchat-pod-ip>:9100/metrics  # Main metrics
curl http://<rocketchat-pod-ip>:9458/metrics  # Microservices metrics
```

**Check Prometheus targets:**
```bash
kubectl port-forward -n monitoring deployment/prometheus-agent 9090:9090
# Open browser to http://localhost:9090/targets
```

**Verify Grafana Cloud credentials secret:**
```bash
kubectl get secret -n monitoring grafana-cloud-credentials
kubectl describe secret -n monitoring grafana-cloud-credentials
```

**Check if ConfigMap references the secret correctly:**
```bash
kubectl get configmap -n monitoring prometheus-agent-config -o yaml | grep -A 10 remote_write
```

**Check remote_write queue status:**
```bash
kubectl logs -n monitoring deployment/prometheus-agent | grep -i "remote_write"
```

**If agent is using too much memory:**

The agent is configured with limits of 512Mi RAM and 250m CPU. If hitting limits:
```bash
# Check current usage
kubectl top pod -n monitoring

# View resource limits
kubectl describe pod -n monitoring -l app=prometheus-agent | grep -A 5 Limits

# If needed, increase limits in prometheus-agent.yaml:
# limits:
#   memory: "768Mi"
#   cpu: "500m"
```

**Verify ephemeral storage isn't filling up:**
```bash
kubectl exec -n monitoring deployment/prometheus-agent -- df -h /prometheus
```

> **Note**: Agent mode uses minimal local storage since metrics are forwarded immediately to Grafana Cloud.

---

### Issue 6: Out of Disk Space

**Symptoms:**
- Pods evicted
- Cannot create new pods
- Logs showing `no space left on device`

**Diagnosis:**
```bash
df -h
df -h | grep /mnt  # Check dedicated volumes
kubectl get pods -A | grep Evicted
lsblk
```

**Solutions:**

**Check which filesystem is full:**
```bash
df -h
du -sh /var/lib/rancher/k3s/*  # K3s data
du -sh /mnt/mongo-data/*       # MongoDB (if using dedicated disk)
du -sh /mnt/prometheus-data/*  # Prometheus (if using dedicated disk)
```

**Clean up evicted pods:**
```bash
kubectl get pods -A | grep Evicted | awk '{print $1, $2}' | xargs -n2 kubectl delete pod -n
```

**Clean Docker images:**
```bash
sudo docker system prune -a
```

**Clean up old logs:**
```bash
sudo journalctl --vacuum-time=3d
```

**Check PVC usage:**
```bash
kubectl get pvc
kubectl exec -it <mongodb-pod> -- df -h
```

**If root disk is full but dedicated disks exist:**

1. Verify mounts are active:
```bash
df -h | grep /mnt
```

2. Check `/etc/fstab` entries:
```bash
cat /etc/fstab | grep /mnt
```

3. Remount if needed:
```bash
sudo mount -a
```

4. Verify PersistentVolumes are using correct paths:
```bash
kubectl get pv -o yaml | grep path
```

**Resize PVC (if using dynamic storage):**
```bash
kubectl edit pvc <pvc-name>
# Update storage size, then restart pod
```

**Add new disk for storage:**

Follow the mounting procedure from deployment guide:
```bash
# Identify new disk
lsblk

# Partition and format
sudo parted /dev/nvmeXn1 -- mklabel gpt
sudo parted -a opt /dev/nvmeXn1 -- mkpart primary ext4 0% 100%
sudo partprobe /dev/nvmeXn1
sudo mkfs.ext4 /dev/nvmeXn1p1

# Mount
sudo mkdir -p /mnt/additional-data
sudo mount /dev/nvmeXn1p1 /mnt/additional-data

# Add to /etc/fstab for persistence
sudo blkid  # Get UUID
# Add line: UUID=<uuid> /mnt/additional-data ext4 defaults,nofail 0 2
```

---

### Issue 7: High Memory Usage / OOM Kills

**Symptoms:**
- Pods restarting frequently
- Logs showing `OOMKilled`
- System running slowly

**Diagnosis:**
```bash
kubectl top nodes
kubectl top pods
kubectl top pods -n monitoring
kubectl describe pod <pod-name> | grep -A 5 State
```

**Solutions:**

**Identify which component is consuming memory:**
```bash
# Check all pods
kubectl top pods -A --sort-by=memory

# Check node-level memory
free -h
```

**For Rocket.Chat pods**, increase resource limits in `values.yaml`:
```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

Apply changes:
```bash
helm upgrade rocketchat -f values.yaml rocketchat/rocketchat
```

**For MongoDB:**
```yaml
mongodb:
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
```

**For Prometheus Agent** (if needed):

Edit `prometheus-agent.yaml` and increase limits:
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "200m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

Apply:
```bash
kubectl apply -f prometheus-agent.yaml
```

> **Important**: Your VM has 7.7 GB RAM total. Ensure combined limits don't exceed available memory. Current optimized configuration:
> - Prometheus Agent: 256Mi-512Mi
> - Rocket.Chat (2 replicas): ~1-2Gi each
> - MongoDB: ~1-2Gi
> - System overhead: ~1-2Gi

---

### Issue 8: Microservices Not Communicating

**Symptoms:**
- Rocket.Chat UI showing errors
- Logs indicating service communication failures
- NATS connection errors in logs

**Diagnosis:**
```bash
kubectl get pods -l app.kubernetes.io/name=rocketchat
kubectl get pods -l app.kubernetes.io/name=nats
kubectl logs <rocketchat-pod> | grep -i nats
kubectl logs <rocketchat-pod> | grep -i error
```

**Solutions:**

**Verify NATS cluster is running:**
```bash
kubectl get pods -l app.kubernetes.io/name=nats
kubectl logs <nats-pod>
```

Expected: 2 NATS pods in Running state.

**Check NATS service:**
```bash
kubectl get svc -l app.kubernetes.io/name=nats
kubectl describe svc rocketchat-nats
```

**Test NATS connectivity from Rocket.Chat pod:**
```bash
kubectl exec -it <rocketchat-pod> -- sh
# Inside pod:
nc -zv rocketchat-nats 4222  # NATS client port
```

**Check Rocket.Chat microservices configuration:**
```bash
kubectl logs <rocketchat-pod> | grep -i "microservices\|nats"
```

Should see NATS connection established messages.

**Verify network policies:**
```bash
kubectl get networkpolicies
```

**Check service discovery:**
```bash
kubectl get svc
kubectl exec -it <rocketchat-pod> -- nslookup rocketchat
kubectl exec -it <rocketchat-pod> -- nslookup rocketchat-nats
```

**Test inter-pod communication:**
```bash
kubectl exec -it <rocketchat-pod> -- wget -O- http://rocketchat:3000/api/info
```

**Restart NATS cluster if needed:**
```bash
kubectl rollout restart statefulset rocketchat-nats
```

---

## Useful Debug Commands

### Port Forward to Service
```bash
kubectl port-forward svc/rocketchat 3000:3000
# Access at http://localhost:3000
```

### Execute Command in Pod
```bash
kubectl exec -it <pod-name> -- /bin/bash
kubectl exec -it <pod-name> -- env  # View environment variables
```

### Copy Files From Pod
```bash
kubectl cp <pod-name>:/path/to/file ./local-file
```

### Watch Resource Changes
```bash
kubectl get pods -w
kubectl get events -w
```

### View Full Pod Spec
```bash
kubectl get pod <pod-name> -o yaml
```

---

### Issue 9: PersistentVolume Not Binding

**Symptoms:**
- PVC stuck in `Pending` state
- Pods unable to start due to volume issues

**Diagnosis:**
```bash
kubectl get pvc
kubectl get pv
kubectl describe pvc <pvc-name>
```

**Common Causes:**
- PersistentVolume not created
- Storage class mismatch
- Node affinity not satisfied
- Mount path doesn't exist or has wrong permissions

**Solutions:**

Check PV status:
```bash
kubectl get pv
kubectl describe pv <pv-name>
```

Verify mount points exist:
```bash
ls -la /mnt/mongo-data
ls -la /mnt/prometheus-data
ls -la /mnt/rocketchat-uploads
```

Check permissions:
```bash
sudo chmod 755 /mnt/mongo-data
sudo chmod 755 /mnt/prometheus-data
sudo chmod 755 /mnt/rocketchat-uploads
sudo chown -R 999:999 /mnt/mongo-data  # MongoDB UID
```

Verify storage class:
```bash
kubectl get storageclass
kubectl describe storageclass local-storage
```

Check node affinity matches:
```bash
kubectl get nodes --show-labels
kubectl get pv <pv-name> -o yaml | grep -A 10 nodeAffinity
```

Manually create PV if missing:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mongo-pv
spec:
  capacity:
    storage: 8Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /mnt/mongo-data
```

---

### Issue 10: Missing Storage Mount Directory

**Symptoms:**
- PV remains in `Available` state, won't bind to PVC
- Pods fail with `FailedMount` errors
- Error: `hostPath path "/mnt/rocketchat-uploads" does not exist`

**Diagnosis:**
```bash
# Check if directories exist
ls -ld /mnt/mongo-data
ls -ld /mnt/prometheus-data
ls -ld /mnt/rocketchat-uploads

# Check what's actually mounted
df -h | grep /mnt
lsblk
```

**Solutions:**

**If directory doesn't exist:**
```bash
# Create missing directories
sudo mkdir -p /mnt/mongo-data
sudo mkdir -p /mnt/prometheus-data
sudo mkdir -p /mnt/rocketchat-uploads

# Set proper permissions
sudo chmod 755 /mnt/mongo-data
sudo chmod 755 /mnt/prometheus-data
sudo chmod 755 /mnt/rocketchat-uploads
```

**If you have dedicated disks, mount them:**
```bash
# Check available disks
lsblk

# Example: Mount nvme3n1p1 for uploads
sudo mount /dev/nvme3n1p1 /mnt/rocketchat-uploads

# Verify mount
df -h | grep /mnt
```

**If you DON'T have a dedicated disk for uploads:**

That's fine! The directory on root filesystem works:
```bash
# Just create the directory
sudo mkdir -p /mnt/rocketchat-uploads
sudo chmod 755 /mnt/rocketchat-uploads

# The PV will use hostPath on root disk
# This is a valid configuration for smaller deployments
```

**After fixing, verify PV binding:**
```bash
kubectl get pv
kubectl get pvc -n rocketchat
# PVCs should now show "Bound" status
```

---

### Issue 11: Mount Point Lost After Reboot

**Symptoms:**
- After server reboot, `/mnt/mongo-data` or `/mnt/prometheus-data` is empty
- Pods fail to start with volume errors

**Diagnosis:**
```bash
df -h | grep /mnt
cat /etc/fstab | grep /mnt
dmesg | grep -i mount
```

**Solutions:**

Check if disks are detected:
```bash
lsblk
sudo blkid
```

Verify `/etc/fstab` entries:
```bash
cat /etc/fstab
```

Should contain:
```
UUID=<uuid> /mnt/mongo-data      ext4 defaults,nofail 0 2
UUID=<uuid> /mnt/prometheus-data ext4 defaults,nofail 0 2
```

Manually remount:
```bash
sudo mount -a
df -h | grep /mnt
```

Check for mount errors:
```bash
sudo journalctl -xe | grep -i mount
```

If UUID changed (rare):
```bash
# Get new UUID
sudo blkid /dev/nvme1n1p1

# Update /etc/fstab with new UUID
sudo nano /etc/fstab

# Remount
sudo mount -a
```

Restart affected pods:
```bash
kubectl rollout restart statefulset rocketchat-mongodb
kubectl rollout restart deployment prometheus-agent -n monitoring
```

---

## Performance Monitoring

### Check Node Resources
```bash
kubectl top nodes
```

### Check Pod Resources
```bash
kubectl top pods
kubectl top pods -n monitoring
```

### View Resource Quotas
```bash
kubectl get resourcequota
kubectl describe resourcequota
```

### Monitor Disk I/O
```bash
# Install iotop if needed
sudo apt-get install iotop

# Monitor I/O
sudo iotop -o

# Check disk stats
iostat -x 1
```

### Check Mount Point Usage
```bash
# Dedicated volumes
df -h /mnt/mongo-data
df -h /mnt/prometheus-data

# Inode usage
df -i /mnt/mongo-data
```

---

## Recovery Procedures

### Restart All Rocket.Chat Pods
```bash
kubectl rollout restart deployment rocketchat
```

### Restart MongoDB
```bash
kubectl rollout restart statefulset rocketchat-mongodb
```

### Force Delete Stuck Pod
```bash
kubectl delete pod <pod-name> --grace-period=0 --force
```

### Reset Entire Deployment
```bash
helm delete rocketchat
kubectl delete pvc -l app.kubernetes.io/name=rocketchat
kubectl delete pvc -l app.kubernetes.io/name=mongodb
helm install rocketchat -f values.yaml rocketchat/rocketchat
```

---

## Getting Help

### Collect Diagnostic Information
```bash
# Create debug bundle
kubectl cluster-info dump > cluster-dump.txt
kubectl get all -A > all-resources.txt
kubectl get events -A --sort-by='.lastTimestamp' > events.txt
helm list -A > helm-releases.txt
```

### Check Helm Release Status
```bash
helm list
helm status rocketchat
helm get values rocketchat
helm get manifest rocketchat
```

---

---

### Issue 12: Deployment Issues - Multiple Pods Failing to Start

**Symptoms:**
- Multiple pods stuck in `Pending`, `ImagePullBackOff`, or `ContainerStatusUnknown`
- MongoDB pod stuck in `Pending`
- Some pods repeatedly restarting
- Certificate not being issued

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -n rocketchat

# Check resource usage
kubectl top nodes
kubectl top pods -n rocketchat

# Check specific pod issues
kubectl describe pod <pod-name> -n rocketchat

# Check events for clues
kubectl get events -n rocketchat --sort-by='.lastTimestamp' | tail -30

# Check if MongoDB volume is mounted
kubectl describe pvc -n rocketchat
```

**Common Causes:**

1. **Insufficient Memory/CPU**
   - Server running out of resources
   - Too many pods trying to start simultaneously
   - MongoDB needs significant RAM to initialize

2. **Image Pull Issues**
   - Network connectivity problems
   - Rate limiting from Docker Hub
   - Authentication required for private registries

3. **Storage Issues**
   - PVC not binding correctly
   - Mount path doesn't exist
   - Permission problems

**Solutions:**

#### If Memory Pressure:

```bash
# Check available memory
free -h

# Check if pods are being evicted
kubectl get events -n rocketchat | grep -i evict

# Temporarily reduce replicas to free memory
kubectl scale deployment rocketchat-rocketchat --replicas=1 -n rocketchat
kubectl scale deployment rocketchat-account --replicas=1 -n rocketchat
kubectl scale deployment rocketchat-authorization --replicas=1 -n rocketchat
kubectl scale deployment rocketchat-ddp-streamer --replicas=1 -n rocketchat
kubectl scale deployment rocketchat-presence --replicas=1 -n rocketchat
kubectl scale deployment rocketchat-stream-hub --replicas=1 -n rocketchat

# Wait for MongoDB to stabilize first
kubectl get pods -n rocketchat -w
```

#### If Image Pull Issues:

```bash
# Check which image is failing
kubectl describe pod <failing-pod> -n rocketchat | grep -i image

# Common fix: Pull images manually on node
sudo docker pull registry.rocket.chat/rocketchat/rocket.chat:7.10.0

# Or try restarting the pod
kubectl delete pod <pod-name> -n rocketchat
```

#### If Storage Issues:

```bash
# Verify PVCs are bound
kubectl get pvc -n rocketchat

# Check mount directories exist
ls -ld /mnt/mongo-data /mnt/rocketchat-uploads

# Verify permissions
sudo chmod 755 /mnt/mongo-data /mnt/rocketchat-uploads
```

#### Gradual Startup Strategy (Recommended):

If your server has limited resources (7.7GB RAM), start components gradually:

```bash
# 1. Delete current deployment
helm uninstall rocketchat -n rocketchat

# 2. Edit values.yaml - reduce microservices replicas
nano values.yaml
# Change all microservice replicas to 1 initially

# 3. Redeploy
helm install rocketchat -f values.yaml rocketchat/rocketchat -n rocketchat

# 4. Wait for MongoDB to be fully ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mongodb -n rocketchat --timeout=300s

# 5. Wait for main Rocket.Chat pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=rocketchat -n rocketchat --timeout=300s

# 6. Scale up gradually after stability
kubectl scale deployment rocketchat-rocketchat --replicas=2 -n rocketchat
```

#### Resource-Optimized values.yaml:

For servers with 7.7GB RAM, consider these settings:

```yaml
# Reduce to 1 replica initially
replicaCount: 1

# MongoDB with reduced resources
mongodb:
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"

# Microservices with lower resources
microservices:
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "250m"
```

---

### Issue 13: Certificate Not Being Issued (Stuck at False)

**Symptoms:**
```bash
kubectl get certificate -n rocketchat
NAME             READY   SECRET           AGE
rocketchat-tls   False   rocketchat-tls   5m
```

**Diagnosis:**
```bash
# Check certificate details
kubectl describe certificate rocketchat-tls -n rocketchat

# Check certificate request
kubectl get certificaterequest -n rocketchat
kubectl describe certificaterequest -n rocketchat

# Check ACME challenge
kubectl get challenge -n rocketchat
kubectl describe challenge -n rocketchat

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=50

# Check if HTTP-01 challenge pod is accessible
kubectl get pods -n rocketchat | grep acme-http-solver
```

**Common Causes:**

1. **Rocket.Chat pods not running yet** - cert-manager waits for application to be healthy
2. **DNS not pointing to server** - HTTP-01 challenge can't reach your server
3. **Port 80 blocked** - Firewall or security group blocking HTTP
4. **Ingress not ready** - NGINX ingress controller issues

**Solutions:**

#### Wait for Rocket.Chat pods first:

The certificate will NOT be issued until Rocket.Chat pods are running and healthy!

```bash
# This is expected - wait for pods to be ready
kubectl get pods -n rocketchat

# Once pods are running, certificate will be issued automatically
# Usually within 2-5 minutes after pods are healthy
```

#### If pods are running but certificate still failing:

```bash
# Check DNS resolution
nslookup k8.canepro.me
dig k8.canepro.me

# Verify port 80 is accessible from internet
curl http://k8.canepro.me/.well-known/acme-challenge/test

# Check challenge details
kubectl describe challenge -n rocketchat

# Manual certificate retry
kubectl delete certificate rocketchat-tls -n rocketchat
# Will be recreated automatically by ingress
```

#### Check firewall rules:

```bash
# On the server
sudo ufw status
sudo iptables -L -n | grep -E '80|443'

# Allow HTTP and HTTPS if blocked
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

---

---

## Quick Issue Index

| # | Issue | Quick Solution |
|---|-------|---------------|
| 0 | Kubectl Permission Denied | [Fix kubectl access](#issue-0-kubectl-permission-denied) |
| 1 | Pods CrashLooping | [Check logs and resources](#issue-1-pods-in-crashloopbackoff) |
| 2 | Certificate Not Issued | [Check DNS and port 80](#issue-2-tls-certificate-not-issued) |
| 3 | Ingress Not Working | [Check ingress controller](#issue-3-ingress-not-working) |
| 4 | MongoDB Connection Issues | [Test connectivity](#issue-4-mongodb-connection-issues) |
| 5 | Prometheus Not Scraping | [Verify secret and endpoints](#issue-5-prometheus-agent-not-scraping-metrics) |
| 6 | Out of Disk Space | [Clean up and resize](#issue-6-out-of-disk-space) |
| 7 | High Memory / OOM | [Adjust resource limits](#issue-7-high-memory-usage--oom-kills) |
| 8 | Microservices Issues | [Check NATS cluster](#issue-8-microservices-not-communicating) |
| 9 | PV Not Binding | [Check mount paths](#issue-9-persistentvolume-not-binding) |
| 10 | Mount Lost After Reboot | [Fix /etc/fstab](#issue-11-mount-point-lost-after-reboot) |
| 11 | Mount Lost After Reboot | [Fix /etc/fstab](#issue-11-mount-point-lost-after-reboot) |
| 12 | Multiple Pods Failing | [Gradual startup](#issue-12-deployment-issues---multiple-pods-failing-to-start) |
| 13 | Certificate Stuck False | [Wait for pods first](#issue-13-certificate-not-being-issued-stuck-at-false) |
| 14 | PodMonitor CRDs Missing | [Apply CRDs](#issue-14-podmonitor-crds-not-found) |
| 15 | Helm Not Installed | [Install Helm](#issue-15-helm-not-installed) |
| 16 | Secret Name Mismatch | [Use grafana-cloud-credentials](#issue-16-grafana-cloud-secret-name-mismatch) |
| 17 | Storage Dirs Missing | [Create directories or use dynamic](#issue-17-storage-directories-dont-exist) |

---

### Issue 14: PodMonitor CRDs Not Found

**Symptoms:**
- Helm install/upgrade fails with "PodMonitor CRD not found"
- Error: `no matches for kind "PodMonitor" in version "monitoring.coreos.com/v1"`

**Diagnosis:**
```bash
kubectl get crd | grep monitoring.coreos.com
```

**Solutions:**

**Install the minimal CRDs:**
```bash
# Apply PodMonitor and ServiceMonitor CRDs
kubectl apply -f podmonitor-crd.yaml

# Verify CRDs are installed
kubectl get crd podmonitors.monitoring.coreos.com
kubectl get crd servicemonitors.monitoring.coreos.com
```

**If CRDs already exist but are outdated:**
```bash
# Delete existing CRDs (Warning: removes all PodMonitor/ServiceMonitor resources)
kubectl delete crd podmonitors.monitoring.coreos.com
kubectl delete crd servicemonitors.monitoring.coreos.com

# Reapply updated CRDs
kubectl apply -f podmonitor-crd.yaml
```

**Verify Rocket.Chat can create PodMonitors:**
```bash
# List PodMonitors after Rocket.Chat deployment
kubectl get podmonitors -n rocketchat

# Describe to see details
kubectl describe podmonitor -n rocketchat
```

> **Note**: These minimal CRDs allow Rocket.Chat's Helm chart to create PodMonitor resources without requiring the full Prometheus Operator stack. The Prometheus Agent (v3.0.0) doesn't need these CRDs but will auto-discover pods via Kubernetes service discovery annotations.

---

---

### Issue 15: Helm Not Installed

**Symptoms:**
```bash
helm repo add rocketchat https://rocketchat.github.io/helm-charts
# Command 'helm' not found
```

**Diagnosis:**
```bash
which helm
helm version
```

**Solutions:**

**Install Helm v3:**
```bash
# Download and install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version

# Should show: version.BuildInfo{Version:"v3.x.x", ...}
```

**Alternative installation methods:**
```bash
# Using snap
sudo snap install helm --classic

# Using package manager (Ubuntu/Debian)
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```

**After installation:**
```bash
# Add Rocket.Chat repository
helm repo add rocketchat https://rocketchat.github.io/helm-charts
helm repo update

# Verify
helm search repo rocketchat
```

---

### Issue 16: Grafana Cloud Secret Name Mismatch

**Symptoms:**
- Deploy script says "Grafana Cloud secret not found" but you created the secret
- Monitoring not deploying even though secret exists
- Secret named differently than what script expects

**Diagnosis:**
```bash
# Check what secret exists
kubectl get secrets -n monitoring

# The prometheus-agent.yaml expects: grafana-cloud-credentials
# The deploy script checks for: grafana-cloud-secret (old name)
```

**Solutions:**

**Option 1: Use correct secret name (recommended):**
```bash
# When creating the secret, use the correct name
cat > grafana-cloud-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: grafana-cloud-credentials    # This is the correct name
  namespace: monitoring
type: Opaque
stringData:
  username: "your-instance-id"
  password: "your-api-key"
EOF

kubectl apply -f grafana-cloud-secret.yaml
```

**Option 2: If you already created with wrong name:**
```bash
# Delete the old secret
kubectl delete secret grafana-cloud-secret -n monitoring

# Create with correct name
kubectl create secret generic grafana-cloud-credentials -n monitoring \
  --from-literal=username="your-instance-id" \
  --from-literal=password="your-api-key"

# Verify
kubectl get secret -n monitoring grafana-cloud-credentials
```

**Verify the fix:**
```bash
# Check secret exists with correct name
kubectl get secret -n monitoring grafana-cloud-credentials

# If deploying monitoring manually
kubectl apply -f prometheus-agent.yaml

# Check prometheus agent is using the secret
kubectl logs -n monitoring deployment/prometheus-agent | grep -i "remote_write"
```

> **Note**: The deploy script has been updated to check for `grafana-cloud-credentials` (not `grafana-cloud-secret`).

---

### Issue 17: Storage Directories Don't Exist

**Symptoms:**
```bash
ls -ld /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads
# ls: cannot access '/mnt/mongo-data': No such file or directory
```

**Diagnosis:**
```bash
# Check if directories exist
ls -la /mnt/

# Check if you have dedicated disks
lsblk
df -h
```

**Solutions:**

**Create directories (works for root filesystem or dedicated disks):**
```bash
# Create all required directories
sudo mkdir -p /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads

# Set proper permissions
sudo chmod 755 /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads

# Verify
ls -ld /mnt/mongo-data /mnt/prometheus-data /mnt/rocketchat-uploads
```

**If you DON'T have dedicated disks:**

That's perfectly fine! k3s includes local-path-provisioner which will automatically create PVCs on the root filesystem:

```bash
# Check storage class
kubectl get storageclass
# Should show: local-path (default)

# Your PVCs will bind automatically without needing the dedicated PVs
kubectl get pvc -n rocketchat
# Will show: Bound to pvc-xxxxx (dynamic provisioning)
```

**If you DO have dedicated disks:**

Mount them first, then create PVs:
```bash
# Mount dedicated disks
sudo mount /dev/nvme1n1p1 /mnt/mongo-data
sudo mount /dev/nvme2n1p1 /mnt/prometheus-data

# Apply PersistentVolumes
kubectl apply -f persistent-volumes.yaml

# Then create PVCs
kubectl apply -f mongo-pvc.yaml
kubectl apply -f rocketchat-uploads-pvc.yaml
```

**Important**: If directories don't exist and you're using hostPath PVs, the PVs won't bind. But with k3s local-path storage (default), everything works automatically!

---

## Additional Resources

- [Rocket.Chat Documentation](https://docs.rocket.chat/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [K3s Documentation](https://docs.k3s.io/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Grafana Cloud Documentation](https://grafana.com/docs/)
- [Prometheus Operator CRDs](https://github.com/prometheus-operator/prometheus-operator)
- [Helm Documentation](https://helm.sh/docs/)

