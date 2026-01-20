# Maintenance Jobs Monitoring Guide

Quick reference for monitoring and managing AKS maintenance CronJobs.

## 🎯 Quick Start

### View Dashboard in Grafana

1. **Import the dashboard:**
   - Go to `https://grafana.canepro.me`
   - Dashboards → Import → Upload JSON
   - Select: `ops/manifests/grafana-dashboard-maintenance-jobs.json`

2. **What you'll see:**
   - ✅ CronJob schedules and next run times
   - ✅ Success/failure history
   - ✅ Job duration trends
   - ✅ Time since last run (alerts if overdue)

### Set Up Alerts (Optional)

Import alert rules from: `ops/manifests/grafana-alerts-maintenance-jobs.yaml`

**Key alerts:**
- 🚨 Job hasn't run on schedule
- 🚨 Job failed to complete
- ⚠️ Job running longer than expected (>10 min)
- ⚠️ Too many stale pods accumulating (>20)

## 📊 What Gets Monitored

### CronJob: `aks-stale-pod-cleanup`
- **Schedule:** Daily at 09:00 UTC (30min after cluster start)
- **Purpose:** Clean up orphaned pods after cluster restart
- **Expected duration:** 10-30 seconds
- **Target phases:** Succeeded, Failed, Unknown

### CronJob: `k3s-image-prune`
- **Schedule:** Weekly on Sunday at 03:00 UTC
- **Purpose:** Remove unused container images to prevent disk pressure
- **Expected duration:** 30-120 seconds
- **Target:** Unused images on all nodes

## 🔍 Metrics Available

The dashboard uses these key metrics from `kube-state-metrics`:

```promql
# When did job last run?
kube_cronjob_status_last_schedule_time{namespace="monitoring"}

# When will it run next?
kube_cronjob_next_schedule_time{namespace="monitoring"}

# Did recent jobs succeed?
kube_job_status_succeeded{namespace="monitoring", job_name=~".*cleanup.*"}

# Did recent jobs fail?
kube_job_status_failed{namespace="monitoring", job_name=~".*cleanup.*"}

# How long did jobs take?
kube_job_status_completion_time - kube_job_status_start_time
```

## 🛠️ Manual Operations

### Check CronJob Status
```bash
# List all maintenance CronJobs
kubectl get cronjobs -n monitoring

# View specific CronJob details
kubectl get cronjob aks-stale-pod-cleanup -n monitoring -o yaml
kubectl get cronjob k3s-image-prune -n monitoring -o yaml
```

### Check Recent Job Runs
```bash
# List recent jobs
kubectl get jobs -n monitoring | grep -E '(cleanup|prune)'

# View job logs
kubectl logs -n monitoring job/aks-stale-pod-cleanup-<timestamp>
kubectl logs -n monitoring job/k3s-image-prune-<timestamp>

# Get latest job logs
kubectl logs -n monitoring -l app=stale-pod-cleanup --tail=50
```

### Manually Trigger Jobs
```bash
# Run stale pod cleanup immediately
kubectl create job --from=cronjob/aks-stale-pod-cleanup manual-cleanup-$(date +%s) -n monitoring

# Run image prune immediately
kubectl create job --from=cronjob/k3s-image-prune manual-prune-$(date +%s) -n monitoring
```

### Manual Cleanup Commands
```bash
# Clean up stale pods directly (bypass job)
kubectl delete pods -A --field-selector=status.phase=Succeeded
kubectl delete pods -A --field-selector=status.phase=Failed
kubectl delete pods -A --field-selector=status.phase=Unknown

# Preview what will be deleted
kubectl get pods -A --field-selector=status.phase=Succeeded
```

## 📈 Dashboard Panels Explained

### Panel 1: Maintenance CronJobs Overview
- Lists all CronJobs with their schedules
- Shows which namespace they run in
- Displays cron schedule expression

### Panel 2: Time Since Last Scheduled Run
- Shows seconds since last execution
- **Green:** Recently run
- **Yellow:** > 1 day since last run
- **Red:** > 2 days since last run (likely stuck)

### Panel 3: Next Scheduled Run
- Shows when each job will run next
- Displayed as "in X hours" or "in X days"
- Useful for planning maintenance windows

### Panel 4: Job Execution History
- Line graph showing success/failure rates
- Separate lines for each job
- Helps identify patterns or recurring failures

### Panel 5: Job Duration
- Shows how long each job took to complete
- Useful for detecting performance degradation
- Alert if jobs start taking significantly longer

### Panel 6: Recent Job Status
- Table showing recent job runs
- Color-coded: Green = Success, Red = Failed
- Quick way to spot failed jobs

## 🚨 Troubleshooting

### Job Hasn't Run
1. Check if CronJob is suspended:
   ```bash
   kubectl get cronjob aks-stale-pod-cleanup -n monitoring -o jsonpath='{.spec.suspend}'
   ```
2. Check cluster time vs schedule:
   ```bash
   date -u  # Should show UTC time
   ```
3. Check for recent jobs:
   ```bash
   kubectl get jobs -n monitoring | grep stale-pod-cleanup
   ```

### Job Failed
1. View job logs:
   ```bash
   kubectl logs -n monitoring job/<job-name>
   ```
2. Check RBAC permissions:
   ```bash
   kubectl auth can-i delete pods --all-namespaces --as=system:serviceaccount:monitoring:stale-pod-cleanup
   ```
3. Try manual run:
   ```bash
   kubectl create job --from=cronjob/aks-stale-pod-cleanup test-run -n monitoring
   ```

### Job Running Too Long
1. Check if job is stuck:
   ```bash
   kubectl get pods -n monitoring -l app=stale-pod-cleanup
   kubectl logs -n monitoring -l app=stale-pod-cleanup --tail=100
   ```
2. If stuck, delete and retry:
   ```bash
   kubectl delete job <job-name> -n monitoring
   kubectl create job --from=cronjob/aks-stale-pod-cleanup retry-$(date +%s) -n monitoring
   ```

### Too Many Stale Pods Accumulating
1. Check if cleanup job is running:
   ```bash
   kubectl get cronjob aks-stale-pod-cleanup -n monitoring
   kubectl get jobs -n monitoring | grep stale-pod-cleanup | head -5
   ```
2. Manually clean up:
   ```bash
   kubectl delete pods -A --field-selector=status.phase=Succeeded
   kubectl delete pods -A --field-selector=status.phase=Failed
   kubectl delete pods -A --field-selector=status.phase=Unknown
   ```
3. Check recent logs for errors:
   ```bash
   kubectl logs -n monitoring -l app=stale-pod-cleanup --tail=200
   ```

## 📚 Related Documentation

- **OPERATIONS.md** - Full day-2 operations guide
- **VERSIONS.md** - Version tracking for maintenance job images
- **ops/manifests/README.md** - Observability stack overview
- **ops/manifests/maintenance-cleanup.yaml** - Image prune CronJob manifest
- **ops/manifests/maintenance-stale-pod-cleanup.yaml** - Pod cleanup CronJob manifest

## 🔗 Quick Links

- **Grafana Dashboard:** `https://grafana.canepro.me`
- **ArgoCD (GitOps):** `https://argocd.canepro.me` → `aks-rocketchat-ops`
- **Dashboard JSON:** `ops/manifests/grafana-dashboard-maintenance-jobs.json`
- **Alert Rules:** `ops/manifests/grafana-alerts-maintenance-jobs.yaml`

---

**Last Updated:** 2026-01-20  
**Cluster:** aks-canepro  
**Monitoring Namespace:** monitoring
