# Rocket.Chat Kubernetes Troubleshooting Guide

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

# MongoDB data directory
du -sh /mnt/mongo-data

# Prometheus data directory
du -sh /mnt/prometheus-data

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
```

Check permissions:
```bash
sudo chmod 755 /mnt/mongo-data
sudo chmod 755 /mnt/prometheus-data
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

### Issue 10: Mount Point Lost After Reboot

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

### Issue 11: PodMonitor CRDs Not Found

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

## Additional Resources

- [Rocket.Chat Documentation](https://docs.rocket.chat/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [K3s Documentation](https://docs.k3s.io/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Grafana Cloud Documentation](https://grafana.com/docs/)
- [Prometheus Operator CRDs](https://github.com/prometheus-operator/prometheus-operator)

