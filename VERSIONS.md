# Software Versions Tracking

This document tracks all software versions used in the AKS Rocket.Chat deployment. Update this file when upgrading any component.

**Last Updated**: 2026-01-29

## Upgrade Status Legend

- ✅ **Up to date**: Already at latest version (updated on date shown)
- ⚠️ **Can upgrade**: Has newer version available, can be upgraded with testing
- ⚠️ **Check latest**: Version not verified, check official source for latest
- ⚠️ **Pinned**: Intentionally pinned (e.g., digest for reproducibility)
- ⚠️ **Deprecated**: Component is deprecated, consider migration path

## Quick Upgrade Reference

**Safe to upgrade now (already updated)**:
- Prometheus Agent v3.8.1 ✅
- OTel Collector v0.142.0 ✅
- Promtail v3.6.0 ✅ (but deprecated)
- Alpine 3.20 (init container) ✅

**Can upgrade with testing**:
- Alpine 3.19 → 3.20 (maintenance job) - Low risk
- NATS Server 2.4 → 2.10.x - **Major version, test carefully**
- NATS Box 0.8.1 → 0.16.2 - Minor version, lower risk
- NATS Config Reloader 0.6.3 → 1.1.0 - **Major version, test carefully**
- Prometheus NATS Exporter 0.9.1 → 0.10.0 - Minor version, lower risk

**Production critical - check before upgrading**:
- Rocket.Chat 7.13.2 - Application version, test thoroughly
- Traefik chart 34.4.1 - Ingress controller, test carefully
- MongoDB Operator 1.6.1 - Database operator, test carefully

## How to Update Versions

1. **Check for latest versions**: See "Update Source" links below or check official repositories
2. **Update the manifest file**: Change the `image:` tag in the corresponding manifest
3. **Test in dev/staging** (if available) before production
4. **Update this file**: Update the version and date in the table below
5. **Commit and let ArgoCD sync**: ArgoCD will automatically deploy the updated version

---

## Observability Stack

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **Prometheus Agent** | `v3.8.1` | `v3.8.1` | ✅ **Up to date** (2026-01-16) | `ops/manifests/prometheus-agent-deployment.yaml` | [Prometheus Releases](https://github.com/prometheus/prometheus/releases) |
| **OpenTelemetry Collector** | `v0.142.0` | `v0.142.0` | ✅ **Up to date** (2026-01-16) | `ops/manifests/otel-collector-deployment.yaml` | [OTel Collector Releases](https://github.com/open-telemetry/opentelemetry-collector-contrib/releases) |
| **Promtail** | `v3.6.0` | `v3.6.0` | ✅ **Up to date** (2026-01-16) ⚠️ **Deprecated** | `ops/manifests/promtail-daemonset.yaml` | [Promtail Releases](https://github.com/grafana/promtail/releases) |
| **kube-state-metrics** | `v2.17.0` | `v2.17.0` | ✅ **Up to date** (2026-01-18) | `ops/manifests/kube-state-metrics.yaml` | [kube-state-metrics Releases](https://github.com/kubernetes/kube-state-metrics/releases) |
| **node-exporter** | `v1.10.2` | `v1.10.2` | ✅ **Up to date** (2026-01-18) | `ops/manifests/node-exporter.yaml` | [node_exporter Releases](https://github.com/prometheus/node_exporter/releases) |
| **Alpine (Init Container)** | `3.20` | `3.20` | ✅ **Up to date** (2026-01-16) | `ops/manifests/prometheus-agent-deployment.yaml` | [Alpine Docker Hub](https://hub.docker.com/_/alpine) |
| **Alpine (Image Prune)** | `3.19` | `3.20` | ⚠️ **Can upgrade** | `ops/manifests/maintenance-cleanup.yaml` | [Alpine Docker Hub](https://hub.docker.com/_/alpine) |
| **Alpine (Pod Cleanup)** | `3.19` | `3.20` | ⚠️ **Can upgrade** | `ops/manifests/maintenance-stale-pod-cleanup.yaml` | [Alpine Docker Hub](https://hub.docker.com/_/alpine) |
| **kubectl (Pod Cleanup)** | `v1.31.4` | `v1.31.x` | ✅ **Up to date** (2026-01-20) | Installed in `ops/manifests/maintenance-stale-pod-cleanup.yaml` | [Kubernetes kubectl](https://kubernetes.io/docs/reference/kubectl/) |
| **TelemetryGen** | `sha256:d9243...` | `latest` | ⚠️ **Pinned** (good for reproducibility) | `ops/manifests/otel-tracegen-job.yaml` | [OTel TelemetryGen](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/cmd/telemetrygen) |

**Note on TelemetryGen**: Uses digest for reproducibility. Update by checking latest image digest at the OTel Collector Contrib repo.

**⚠️ Important Note on Promtail**: Promtail is deprecated in favor of Grafana Alloy. Promtail entered LTS (Long-Term Support) on February 13, 2025, and will reach End of Life (EOL) on March 2, 2026. Consider migrating to Grafana Alloy for long-term support. See [Promtail Deprecation Notice](https://grafana.com/blog/2025/02/13/grafana-loki-3.4-standardized-storage-config-sizing-guidance-and-promtail-merging-into-alloy/) for details.

---

## NATS Stack

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **NATS Server** | `2.4-alpine` | `2.10.24` | ⚠️ **Can upgrade** (major version jump, test carefully) | `ops/manifests/rocketchat-nats.yaml` | [NATS Releases](https://github.com/nats-io/nats-server/releases) |
| **NATS Box** | `0.8.1` | `0.16.2` | ⚠️ **Can upgrade** (minor version, lower risk) | `ops/manifests/rocketchat-nats.yaml` | [NATS Box Releases](https://github.com/nats-io/nats-box/releases) |
| **NATS Config Reloader** | `0.6.3` | `1.1.0` | ⚠️ **Can upgrade** (major version jump, test carefully) | `ops/manifests/rocketchat-nats.yaml` | [NATS Config Reloader](https://github.com/nats-io/nats-server-config-reloader/releases) |
| **Prometheus NATS Exporter** | `0.9.1` | `0.10.0` | ⚠️ **Can upgrade** (minor version, lower risk) | `ops/manifests/rocketchat-nats.yaml` | [NATS Exporter Releases](https://github.com/nats-io/prometheus-nats-exporter/releases) |
| **NATS Helm Chart** | `0.15.1` | `latest` | ⚠️ **Check latest** (managed by RocketChat chart) | `ops/manifests/rocketchat-nats.yaml` | [NATS Helm Chart](https://github.com/nats-io/k8s/tree/main/helm/charts/nats) |

---

## Infrastructure Components

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **Rocket.Chat Application** | `8.0.1` | `8.0.1` | ✅ **Up to date** (2026-01-20) | `values.yaml` | [Rocket.Chat Releases](https://github.com/RocketChat/Rocket.Chat/releases) |
| **Rocket.Chat Helm Chart** | `6.29.0` | `Check latest` | ⚠️ **Check latest** (test chart upgrades carefully) | `GrafanaLocal/argocd/applications/aks-rocketchat-helm.yaml` | [Rocket.Chat Helm Charts](https://github.com/RocketChat/charts) |
| **Traefik Helm Chart** | `34.4.1` | `Check latest` | ⚠️ **Check latest** (ingress controller, test carefully) | `GrafanaLocal/argocd/applications/aks-traefik.yaml` | [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart) |
| **MongoDB Operator Helm Chart** | `1.6.1` | `Check latest` | ⚠️ **Check latest** (database operator, test carefully) | `GrafanaLocal/argocd/applications/aks-rocketchat-mongodb-operator.yaml` | [MongoDB Operator](https://github.com/mongodb/mongodb-kubernetes-operator) |
| **External Secrets Operator Helm Chart** | `0.10.5` | `Check latest` | ⚠️ **Check latest** (secret management, test carefully) | `GrafanaLocal/argocd/applications/aks-rocketchat-external-secrets.yaml` | [ESO Releases](https://github.com/external-secrets/external-secrets/releases) |
| **cert-manager** | See ArgoCD App | `Check latest` | ⚠️ **Check latest** (TLS critical, test carefully) | ArgoCD managed | [cert-manager Releases](https://github.com/cert-manager/cert-manager/releases) |

---

## CI/CD Stack

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **Jenkins Helm Chart** | `5.8.110` | `5.8.110` | ✅ **Up to date** (2026-01-19) | `GrafanaLocal/argocd/applications/aks-jenkins.yaml` | [Jenkins Helm Charts](https://github.com/jenkinsci/helm-charts/releases) |
| **Jenkins LTS** | `2.541.1-lts-jdk21` | `2.541.1-lts` | ✅ **Up to date** (2026-01-27) | `jenkins-values.yaml` | [Jenkins Releases](https://www.jenkins.io/changelog-stable/) |

**Jenkins Role**: CI validation only (PR checks, linting, policy validation)
- ✅ Configured with latest LTS + Java 21 (best practice)
- ✅ Security hardened (CSRF, no controller executors, RBAC)
- ✅ Dynamic Kubernetes agents (terraform, helm, default)
- ✅ Prometheus metrics enabled
- ⚠️ To enable applies: Update RBAC + JCasC configuration

---

## Version Update Procedure

### Quick Update Steps

1. **Identify the component** to update from the table above
2. **Check latest version** from the Update Source
3. **Edit the manifest file** listed in the Location column
4. **Change the `image:` tag** to the new version
5. **Update VERSIONS.md** with new version and date
6. **Commit and push** - ArgoCD will auto-sync the change

### Example: Updating Prometheus Agent

```bash
# 1. Check current version in manifest
grep "image:" ops/manifests/prometheus-agent-deployment.yaml
# Current output: image: prom/prometheus:v3.8.1

# 2. Check latest version at https://github.com/prometheus/prometheus/releases
# Example: Latest is v3.9.0

# 3. Update the manifest file
# Edit: ops/manifests/prometheus-agent-deployment.yaml
# Change: image: prom/prometheus:v3.8.1
# To:     image: prom/prometheus:v3.9.0

# 4. Update this file (VERSIONS.md)
# Edit the "Current Version" column in the Observability Stack table above
# Change: v3.8.1 → v3.9.0

# 5. Commit the changes
git add ops/manifests/prometheus-agent-deployment.yaml VERSIONS.md
git commit -m "chore: Upgrade Prometheus Agent to v3.9.0"

# 6. Push and ArgoCD will auto-sync the change to the cluster
git push
```

### Verifying Updates

After ArgoCD syncs:

```bash
# Check the deployed image version
kubectl get deployment prometheus-agent -n monitoring -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check pod is running with new version
kubectl get pods -n monitoring -l app=prometheus-agent -o wide

# Check logs for any errors
kubectl logs -n monitoring -l app=prometheus-agent --tail=50
```

---

## Security Considerations

- **Regular Updates**: Check for updates monthly or when security advisories are published
- **Breaking Changes**: Review release notes for breaking changes before upgrading
- **Testing**: Test updates in a non-production environment when possible
- **Backup**: Ensure backups are current before major version upgrades

---

## Terraform & Infrastructure Tools

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **Terraform** | `>= 1.0` | `Check latest` | ⚠️ **Check latest** (test Terraform upgrades carefully) | `terraform/main.tf` | [Terraform Releases](https://github.com/hashicorp/terraform/releases) |
| **Azure Provider** | `~> 3.0` | `Check latest` | ⚠️ **Check latest** (test provider upgrades carefully) | `terraform/main.tf` | [Azure Provider Releases](https://github.com/hashicorp/terraform-provider-azurerm/releases) |
| **Kubernetes Version** | `latest` | `Check latest` | ⚠️ **Check latest** (AKS managed, test upgrades carefully) | `terraform/aks.tf` | [AKS Supported Versions](https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions) |

---

## Version Compatibility Notes

- **Prometheus Agent** `v3.8.1` (upgraded from v2.45.0) - `--enable-feature=agent` flag supported
- **OTel Collector** `v0.142.0` (upgraded from v0.88.0) - check compatibility with your observability hub
- **Promtail** `v3.6.0` (upgraded from v2.9.3) - should be compatible with your Loki version at `observability.canepro.me`
- **NATS Server** `2.4-alpine` (can upgrade to 2.10.24) - major version jump, test carefully
- **Terraform** `>= 1.0` - latest stable recommended for Azure provider compatibility
- **Azure Provider** `~> 3.0` - check for provider v4.0 migration guide before upgrading
