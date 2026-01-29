# RocketChat Kubernetes Platform

Production-grade RocketChat deployment on Azure Kubernetes Service (AKS) using GitOps principles with ArgoCD.

## Overview

This repository contains the complete infrastructure-as-code for deploying and operating RocketChat at scale:

- **Application**: RocketChat monolith + microservices (account, authorization, presence, ddp-streamer)
- **Database**: MongoDB via Community Kubernetes Operator
- **Messaging**: NATS for microservices communication
- **Ingress**: Traefik with automatic TLS via cert-manager
- **Observability**: Prometheus, Grafana, Loki, Tempo (hosted on separate OKE hub cluster)
- **Secrets**: External Secrets Operator + Azure Key Vault
- **CI/CD**: ArgoCD (GitOps) + Jenkins (validation)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AKS Cluster                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  RocketChat  │  │   MongoDB    │  │    Observability     │  │
│  │  (Helm)      │  │  (Operator)  │  │  (Prometheus Agent)  │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│           │                │                    │               │
│           └────────────────┴────────────────────┘               │
│                            │                                    │
│                     ┌──────┴──────┐                            │
│                     │   Traefik   │                            │
│                     │  (Ingress)  │                            │
│                     └─────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
                             │
                       k8.canepro.me
```

For detailed architecture diagrams, see [DIAGRAM.md](DIAGRAM.md).

## Quick Start

### Upgrade RocketChat Version

```bash
# 1. Edit values.yaml - change image.tag
vim values.yaml

# 2. Commit and push
git add values.yaml
git commit -m "chore: upgrade RocketChat to X.Y.Z"
git push origin master
```

ArgoCD automatically syncs changes within 3 minutes.

### Manual Cluster Operations

```bash
# Start cluster (if stopped)
az aks start --resource-group rg-canepro-aks --name aks-canepro

# Stop cluster
az aks stop --resource-group rg-canepro-aks --name aks-canepro

# Check cluster status
az aks show --resource-group rg-canepro-aks --name aks-canepro --query powerState
```

## Repository Structure

```
.
├── values.yaml                 # RocketChat Helm values (versions, scaling, config)
├── ops/
│   ├── kustomization.yaml      # Kustomize entrypoint for ops manifests
│   ├── manifests/              # Raw K8s manifests (PVCs, monitoring, maintenance)
│   └── secrets/                # ExternalSecret definitions (GitOps secrets)
├── terraform/                  # AKS infrastructure + automation schedules
├── .jenkins/                   # CI pipeline definitions
├── OPERATIONS.md               # Day-2 operations runbook
├── JENKINS_DEPLOYMENT.md       # Jenkins setup + runbook
├── VERSIONS.md                 # Component version tracking
├── DIAGRAM.md                  # Architecture diagrams
└── TROUBLESHOOTING_DNS_TLS.md  # DNS/TLS troubleshooting
```

## GitOps Model

This repository follows a **Split-App Pattern** with ArgoCD:

| Application | Source | Manages |
|-------------|--------|---------|
| `aks-rocketchat-helm` | `values.yaml` | RocketChat application stack |
| `aks-rocketchat-ops` | `ops/` | Infrastructure (storage, monitoring, jobs) |
| `aks-rocketchat-secrets` | `ops/secrets/` | External Secrets definitions |

**Deployment Flow**:
1. Commit changes to `master` branch
2. ArgoCD detects changes (3-min sync interval)
3. ArgoCD applies changes to cluster
4. Rollback via `git revert` if needed

## Configuration

### Key Files

| File | Purpose |
|------|---------|
| `values.yaml` | RocketChat version, replicas, resources, feature flags |
| `ops/manifests/mongodb-community.example.yaml` | MongoDB cluster configuration |
| `terraform/variables.tf` | Infrastructure parameters |
| `jenkins-values.yaml` | Jenkins Helm configuration |

### Secrets Management

Secrets are managed via GitOps using External Secrets Operator:

```yaml
# ops/secrets/externalsecret-example.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rocketchat-mongodb
spec:
  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore
  target:
    name: rocketchat-mongodb
  data:
    - secretKey: mongo-uri
      remoteRef:
        key: rocketchat-mongodb-uri
```

**Never commit secrets to this repository.** Store values in Azure Key Vault.

## Operations

### Monitoring

| Service | URL |
|---------|-----|
| ArgoCD | https://argocd.canepro.me |
| Grafana | https://grafana.canepro.me |
| Jenkins | https://jenkins.canepro.me |
| RocketChat | https://k8.canepro.me |

### Cost Optimization

The cluster runs on an automated schedule to minimize costs:

- **Runtime**: Weekdays 16:00-23:00 UTC (7 hours/day)
- **Monthly Hours**: ~140 hours
- **Estimated Cost**: £55-70/month

Schedule is managed via Terraform in `terraform/automation.tf`.

### Maintenance Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `k3s-image-prune` | Sunday 03:00 UTC | Remove unused container images |
| `aks-stale-pod-cleanup` | Daily 09:00 UTC | Clean up pods after cluster restart |

## CI/CD Pipeline

### Jenkins (Validation)

Jenkins performs CI validation on pull requests:

- Terraform: `fmt -check`, `validate`, `plan`
- Helm: `template` + `kubeconform`
- YAML: `yamllint`
- Security: `tfsec`, `checkov`, `trivy`

This repo also runs two scheduled “automation” jobs that report to GitHub so you don’t have to check Jenkins daily:
- **Version updates**: `.jenkins/version-check.Jenkinsfile` → breaking issue + non-breaking PR (de-duped)
- **Security validation**: `.jenkins/security-validation.Jenkinsfile` → issue/PR updates (de-duped)

See:
- `.jenkins/VERSION_CHECKING.md`
- `.jenkins/SECURITY_VALIDATION.md`

### ArgoCD (Deployment)

ArgoCD handles all deployments via GitOps:

- Auto-sync enabled on `master` branch
- Self-heal enabled (drift correction)
- Prune enabled (remove orphaned resources)

## Documentation

| Document | Description |
|----------|-------------|
| [OPERATIONS.md](OPERATIONS.md) | Day-2 operations, upgrades, troubleshooting |
| [DIAGRAM.md](DIAGRAM.md) | Architecture and data flow diagrams |
| [VERSIONS.md](VERSIONS.md) | Component version tracking |
| [JENKINS_DEPLOYMENT.md](JENKINS_DEPLOYMENT.md) | Jenkins setup and configuration |
| [TROUBLESHOOTING_DNS_TLS.md](TROUBLESHOOTING_DNS_TLS.md) | DNS and TLS troubleshooting |
| [MIGRATION_STATUS.md](MIGRATION_STATUS.md) | Migration progress tracking |
| [terraform/README.md](terraform/README.md) | Infrastructure documentation |
| [.jenkins/README.md](.jenkins/README.md) | Jenkins pipelines overview |

## Prerequisites

- Azure CLI with AKS credentials
- `kubectl` configured for the cluster
- Git access to this repository

For emergency access or initial setup, see [OPERATIONS.md](OPERATIONS.md).

## Contributing

1. Create a feature branch from `master`
2. Make changes and test locally where possible
3. Submit a pull request
4. Jenkins validates the changes
5. Merge to `master` triggers ArgoCD deployment

## License

See [LICENSE](LICENSE) for details.
