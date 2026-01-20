# Maintenance Monitoring Setup Summary

## ✅ What Was Created (2026-01-20)

### 1. Automated Cleanup Jobs

#### Stale Pod Cleanup CronJob
- **File:** `ops/manifests/maintenance-stale-pod-cleanup.yaml`
- **Schedule:** Daily at 09:00 UTC (30 min after cluster start at 08:30)
- **Purpose:** Clean up orphaned pods after cluster auto-shutdown/restart
- **Targets:** Succeeded, Failed, Unknown pods
- **RBAC:** Includes ServiceAccount, ClusterRole, ClusterRoleBinding

#### Cleanup Script (Reference)
- **File:** `ops/scripts/cleanup-stale-pods.sh`
- **Purpose:** Standalone script version (for reference/manual use)

### 2. Monitoring Dashboard

#### Grafana Dashboard
- **File:** `ops/manifests/grafana-dashboard-maintenance-jobs.json`
- **Panels:** 6 panels showing job schedules, status, duration, and history
- **Data Source:** Prometheus (kube-state-metrics)
- **Import:** Upload to Grafana via Dashboards → Import

#### Alert Rules (Optional)
- **File:** `ops/manifests/grafana-alerts-maintenance-jobs.yaml`
- **Alerts:** 5 alerts covering job failures, delays, and pod accumulation
- **Import:** Add to Grafana Alerting or use Provisioning

### 3. Documentation

#### Maintenance Monitoring Guide
- **File:** `ops/MAINTENANCE_MONITORING.md`
- **Content:** Complete guide for monitoring, troubleshooting, and manual operations
- **Audience:** Operators managing the cluster

#### Operations Guide Updates
- **File:** `OPERATIONS.md`
- **Updates:** Added stale pod cleanup section with commands and dashboard info

#### Version Tracking Updates
- **File:** `VERSIONS.md`
- **Updates:** Added `bitnami/kubectl:1.31` for maintenance jobs

#### README Updates
- **Files:** `README.md`, `ops/manifests/README.md`
- **Updates:** Added maintenance monitoring references

### 4. GitOps Configuration

#### Kustomization Update
- **File:** `ops/kustomization.yaml`
- **Changes:** Added `maintenance-stale-pod-cleanup.yaml` to resources

## 🚀 Next Steps

### Step 1: Clean Up Current Stale Pods (Immediate)

Run these commands now to clean up the 15 stale pods you identified:

```bash
kubectl delete pods --field-selector=status.phase=Succeeded -A
kubectl delete pods --field-selector=status.phase=Failed -A
kubectl delete pods --field-selector=status.phase=Unknown -A
```

Expected result: 15 pods deleted (8 Completed + 6 Unknown + 1 Error)

### Step 2: Deploy the New CronJob (GitOps)

Sync the ArgoCD application to deploy the new cleanup job:

```bash
# Login to ArgoCD
argocd login argocd.canepro.me --grpc-web

# Sync the ops application
argocd app sync aks-rocketchat-ops

# Or via UI
# https://argocd.canepro.me → aks-rocketchat-ops → Sync
```

Verify deployment:

```bash
kubectl get cronjob aks-stale-pod-cleanup -n monitoring
kubectl get serviceaccount stale-pod-cleanup -n monitoring
kubectl get clusterrole stale-pod-cleanup
```

### Step 3: Import Grafana Dashboard

1. Open Grafana: `https://observability.canepro.me`
2. Navigate to **Dashboards** → **Import**
3. Click **Upload JSON file**
4. Select: `ops/manifests/grafana-dashboard-maintenance-jobs.json`
5. Choose your Prometheus datasource
6. Click **Import**

### Step 4: Set Up Alerts (Optional)

Choose one of these methods:

#### Option A: Manual Alert Creation
1. Open Grafana → **Alerting** → **Alert rules**
2. Use queries from `ops/manifests/grafana-alerts-maintenance-jobs.yaml`
3. Create alert rules manually

#### Option B: Grafana Provisioning (Recommended for GitOps)
1. Add alert rules to your Grafana Provisioning config
2. Deploy via your Grafana Helm chart or ConfigMap

### Step 5: Test the Setup (Tomorrow Morning)

After the cluster restarts tomorrow (2026-01-21 08:30), verify:

1. **CronJob runs automatically at 09:00 UTC:**
   ```bash
   kubectl get jobs -n monitoring | grep stale-pod-cleanup
   ```

2. **Check job logs:**
   ```bash
   kubectl logs -n monitoring -l app=stale-pod-cleanup --tail=50
   ```

3. **Verify stale pods are cleaned:**
   ```bash
   kubectl get pods -A | grep -E '(Completed|Unknown|Error)'
   ```

4. **Check Grafana dashboard:**
   - Open: `https://observability.canepro.me`
   - Go to: AKS Maintenance Jobs dashboard
   - Verify: "Time Since Last Scheduled Run" shows recent execution

## 📊 Dashboard Overview

The Grafana dashboard includes:

| Panel | Purpose | What to Watch |
|-------|---------|---------------|
| **Maintenance CronJobs Overview** | Lists all CronJobs | Verify both jobs are listed |
| **Time Since Last Scheduled Run** | Shows when jobs last ran | Should be green (<24h for daily, <7d for weekly) |
| **Next Scheduled Run** | Shows next execution time | Verify schedule looks correct |
| **Job Execution History** | Success/failure trends | Should show mostly green (success) |
| **Job Duration** | How long jobs take | Should be <2 min for both jobs |
| **Recent Job Status** | Latest job results | Green = success, Red = failed |

## 🔧 Troubleshooting

### Dashboard Shows "No Data"

**Possible causes:**
1. CronJob hasn't run yet (wait for first scheduled run)
2. Wrong Prometheus datasource selected
3. kube-state-metrics not deployed or not scraping

**Fix:**
```bash
# Verify kube-state-metrics is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-state-metrics

# Check if metrics are being scraped
kubectl exec -n monitoring deploy/prometheus-agent -- \
  wget -qO- http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="kube-state-metrics")'
```

### CronJob Not Deploying

**Possible causes:**
1. ArgoCD sync failed
2. RBAC conflicts
3. Namespace doesn't exist

**Fix:**
```bash
# Check ArgoCD sync status
argocd app get aks-rocketchat-ops

# Check for errors
kubectl get events -n monitoring --sort-by='.lastTimestamp' | grep -i error

# Manually apply
kubectl apply -f ops/manifests/maintenance-stale-pod-cleanup.yaml
```

### Job Runs But Fails

**Possible causes:**
1. Insufficient RBAC permissions
2. kubectl image pull issues
3. API server connectivity

**Fix:**
```bash
# Check job logs
kubectl logs -n monitoring job/<job-name>

# Verify RBAC
kubectl auth can-i delete pods --all-namespaces \
  --as=system:serviceaccount:monitoring:stale-pod-cleanup

# Test manually
kubectl create job --from=cronjob/aks-stale-pod-cleanup test-$(date +%s) -n monitoring
```

## 📚 Documentation Reference

| Document | Purpose | When to Use |
|----------|---------|-------------|
| `ops/MAINTENANCE_MONITORING.md` | Complete monitoring guide | Day-to-day operations, troubleshooting |
| `OPERATIONS.md` | Full day-2 operations guide | Upgrades, scaling, maintenance |
| `VERSIONS.md` | Version tracking | Before upgrading components |
| `ops/manifests/README.md` | Observability overview | Understanding the stack |

## 🎯 Success Criteria

After completing all steps, you should have:

- ✅ All current stale pods cleaned up (0 Succeeded/Failed/Unknown pods)
- ✅ New CronJob deployed and visible in `kubectl get cronjobs -n monitoring`
- ✅ Grafana dashboard imported and showing data (may need first run)
- ✅ Documentation updated and committed to git
- ✅ (Optional) Alerts configured in Grafana

## 🔄 Ongoing Maintenance

**Daily** (Automated):
- Stale pod cleanup runs at 09:00 UTC
- Check dashboard if you notice pod count growing

**Weekly** (Automated):
- Image prune runs Sunday 03:00 UTC
- Check dashboard for successful completion

**Monthly** (Manual):
- Review dashboard for any trends or issues
- Check job duration hasn't increased significantly
- Verify alerts are working (if configured)

## 🤝 Support

If you encounter issues:
1. Check `ops/MAINTENANCE_MONITORING.md` troubleshooting section
2. Review recent job logs: `kubectl logs -n monitoring -l app=stale-pod-cleanup --tail=100`
3. Check ArgoCD app health: `argocd app get aks-rocketchat-ops`

---

**Setup Date:** 2026-01-20  
**Cluster:** aks-canepro  
**Monitoring:** Grafana + Prometheus + kube-state-metrics  
**GitOps:** ArgoCD
