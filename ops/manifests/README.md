# Observability Manifests

This directory contains Kubernetes manifests for observability stack components that ship metrics, traces, and logs from the AKS cluster to the central observability hub.

## Overview

These manifests deploy:
- **Prometheus Agent**: Scrapes metrics and forwards them to Mimir/Grafana
- **OpenTelemetry Collector**: Receives traces and forwards them to Tempo/Grafana
- **Promtail**: Collects pod logs and ships them to Loki/Grafana

## File Structure

### Prometheus Agent
- `prometheus-agent-configmap.yaml` - Configuration for scraping metrics
- `prometheus-agent-deployment.yaml` - Deployment running Prometheus Agent
- `prometheus-agent-rbac.yaml` - RBAC permissions for pod/service discovery

### OpenTelemetry Collector
- `otel-collector-configmap.yaml` - Configuration for trace collection and export
- `otel-collector-deployment.yaml` - Deployment running OTel Collector
- `otel-collector-service.yaml` - Service exposing OTLP endpoints
- `otel-tracegen-job.yaml` - Optional job to generate test traces for verification

### Promtail (Log Shipping)
- `promtail-configmap.yaml` - Configuration for log collection from pods
- `promtail-daemonset.yaml` - DaemonSet running Promtail on each node
- `promtail-rbac.yaml` - RBAC permissions for pod discovery and log access

## Version Tracking

All component versions are tracked in `VERSIONS.md` in the repository root. See that file for:
- Current versions of all components
- Latest version information
- Update procedures
- Compatibility notes

**⚠️ Important**: Before upgrading any component, check `VERSIONS.md` for latest versions and compatibility notes.

## Configuration

### Credentials

All components use the `observability-credentials` Secret in the `monitoring` namespace for authentication to the central hub. This secret contains:
- `username`: Basic auth username
- `password`: Basic auth password

### Endpoints

All components connect to `https://observability.canepro.me`:
- **Metrics** (Prometheus Agent): `/api/v1/write` (Mimir remote_write endpoint)
- **Traces** (OTel Collector): `/v1/traces` (Tempo OTLP/HTTP endpoint)
- **Logs** (Promtail): `/loki/api/v1/push` (Loki push API endpoint)

### Cluster Labels

All components add the `cluster=aks-canepro` label/attribute to their data, allowing you to filter by cluster in Grafana.

## Deployment

These manifests are managed via GitOps (ArgoCD). Changes are automatically synced to the cluster.

To manually deploy:
```bash
kubectl apply -k ops/
```

## Troubleshooting

See `observability-verification.md` in this directory for:
- Verification procedures
- Troubleshooting steps
- Common issues and solutions

## Grafana Dashboards

Pre-built Grafana dashboards are available in this directory for monitoring various aspects of the cluster:

### Available Dashboards

#### AKS Maintenance Jobs (`grafana-dashboard-maintenance-jobs.json`)
Monitors all maintenance CronJobs including:
- `k3s-image-prune` (weekly image cleanup)
- `aks-stale-pod-cleanup` (daily pod cleanup after cluster restart)

**Panels include:**
- CronJob schedules and status
- Time since last run / next scheduled run
- Job success/failure history
- Job duration trends
- Recent execution status

**To import:**
1. Open Grafana at `https://grafana.canepro.me`
2. Navigate to **Dashboards** → **Import**
3. Upload the JSON file from this directory
4. Select your Prometheus datasource
5. Click **Import**

**Recommended alerts:**
- Alert if jobs haven't run on schedule (> expected interval)
- Alert on job failures (2+ consecutive failures)
- Alert on long job durations (> 5 minutes)

## Related Documentation

- `VERSIONS.md` (root) - Version tracking and update procedures
- `MIGRATION_STATUS.md` (root) - Overall migration status and observability verification
- `observability-verification.md` (this directory) - Verification and troubleshooting guide
- `OPERATIONS.md` (root) - Day-2 operations guide including maintenance jobs
