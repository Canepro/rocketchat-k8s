# Jenkins Deployment Guide

This guide covers deploying a general-purpose Jenkins CI server on AKS for CI validation across multiple projects.

**Last Updated**: 2026-01-19

---

## 📋 Overview

### Jenkins Configuration
- **Version**: Jenkins LTS 2.516.3 with Java 21
- **Helm Chart**: 5.8.110 (latest)
- **Purpose**: General-purpose CI server for all projects on the cluster
- **Role**: CI validation only (no applies by default)
- **Access**: `https://jenkins.canepro.me`
- **Secrets**: Managed via External Secrets Operator + Azure Key Vault

### What Jenkins Does
✅ **CI Validation (Default)**:
- PR validation jobs (lint, policy checks)
- `terraform fmt -check`, `terraform validate`, `terraform plan` (read-only)
- `helm template` + `kubeconform` for manifest validation
- YAML linting (`yamllint`)
- Policy checks (OPA/Conftest)

❌ **NOT Done by Default**:
- `terraform apply` (Cloud Shell only - can be enabled)
- `kubectl apply` (ArgoCD deploys - can be enabled)

### Architecture
```
GitHub PR → Webhook → Jenkins → Dynamic K8s Agents → PR Status Check
                                     ↓
                              (terraform/helm/default)
```

---

## 🚀 Quick Deployment (5 Steps)

### Prerequisites
- ✅ AKS cluster running (`aks-canepro`)
- ✅ ArgoCD deployed and syncing
- ✅ External Secrets Operator deployed
- ✅ Azure Key Vault provisioned (`aks-canepro-kv-e8d280`)
- ✅ Traefik ingress controller deployed
- ✅ cert-manager deployed with Let's Encrypt ClusterIssuer

### Step 1: Add Secrets to Azure Key Vault

You need to add 3 secrets to Azure Key Vault via Terraform:

```bash
# Navigate to terraform directory
cd terraform

# Edit terraform.tfvars (gitignored) and add:
# jenkins_admin_username = "admin"  # Or your preferred username
# jenkins_admin_password = "STRONG_PASSWORD_HERE"
# jenkins_github_token = "ghp_YOUR_GITHUB_TOKEN_HERE"

# Apply Terraform to create secrets in Key Vault
terraform plan  # Verify changes
terraform apply  # Create secrets
```

**GitHub Token Scopes Required**:
- `repo` (full control of private repositories)
- `admin:repo_hook` (webhook management)

**Generate GitHub Token**: [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)

### Step 2: Apply ArgoCD Application

```bash
# Apply Jenkins ArgoCD application
kubectl apply -f GrafanaLocal/argocd/applications/aks-jenkins.yaml

# Verify ArgoCD picked it up
kubectl get application -n argocd aks-jenkins

# Expected output:
# NAME          SYNC STATUS   HEALTH STATUS
# aks-jenkins   Synced        Healthy
```

### Step 3: Monitor Deployment

```bash
# Watch pods come up (takes ~2-3 minutes)
kubectl get pods -n jenkins -w

# Expected pods:
# NAME                       READY   STATUS    RESTARTS   AGE
# jenkins-0                  2/2     Running   0          2m
```

### Step 4: Verify TLS Certificate

```bash
# Check certificate issued (takes ~1-2 minutes)
kubectl get certificate -n jenkins

# Expected output:
# NAME          READY   SECRET        AGE
# jenkins-tls   True    jenkins-tls   2m

# If stuck in "Issuing", check cert-manager logs:
kubectl logs -n cert-manager -l app=cert-manager
```

### Step 5: Access Jenkins

```bash
# Get admin password (from Key Vault via External Secret)
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d

# Open browser to: https://jenkins.canepro.me
# Login with:
#   Username: admin (or your custom username)
#   Password: <password from above>
```

---

## 🔧 Configuration

### Jenkins Configuration as Code (JCasC)

Jenkins is configured via JCasC in `jenkins-values.yaml`. Key configurations:

**Security**:
- CSRF protection enabled (required for Traefik)
- No executors on controller (agents only)
- RBAC via `loggedInUsersCanDoAnything` (can be customized)

**Agents**:
- `default`: Basic Ubuntu agent for general CI tasks
- `terraform`: Terraform + Azure CLI for infrastructure validation
- `helm`: kubectl + helm + kubeconform for manifest validation

**Plugins**:
- Latest versions of essential plugins (auto-updates)
- GitHub integration (branch source, webhooks)
- Kubernetes dynamic agents
- Security plugins (CSRF, RBAC, credentials)

### Customizing Configuration

Edit `jenkins-values.yaml` and commit:

```yaml
controller:
  JCasC:
    configScripts:
      custom-config: |
        # Your custom JCasC YAML here
```

ArgoCD will auto-sync the changes.

---

## 🎯 Creating CI Jobs

### Example: Terraform PR Validation

Create a Jenkinsfile in any of your project repositories:

```groovy
pipeline {
  agent {
    kubernetes {
      label 'terraform'
      defaultContainer 'terraform'
    }
  }
  
  stages {
    stage('Terraform Format Check') {
      steps {
        sh 'terraform fmt -check -recursive'
      }
    }
    
    stage('Terraform Validate') {
      steps {
        sh 'terraform init -backend=false'
        sh 'terraform validate'
      }
    }
    
    stage('Terraform Plan') {
      steps {
        sh 'terraform init'
        sh 'terraform plan -no-color'
      }
    }
  }
}
```

### Example: Helm Validation

```groovy
pipeline {
  agent {
    kubernetes {
      label 'helm'
      defaultContainer 'helm'
    }
  }
  
  stages {
    stage('Helm Template') {
      steps {
        sh 'helm template . -f values.yaml > manifests.yaml'
      }
    }
    
    stage('Kubeconform Validate') {
      steps {
        sh 'kubeconform -strict manifests.yaml'
      }
    }
    
    stage('YAML Lint') {
      steps {
        sh 'yamllint -c .yamllint *.yaml'
      }
    }
  }
}
```

### Example: OPA/Conftest Policy Check

```groovy
pipeline {
  agent {
    kubernetes {
      label 'default'
      defaultContainer 'jnlp'
    }
  }
  
  stages {
    stage('Install Conftest') {
      steps {
        sh 'wget https://github.com/open-policy-agent/conftest/releases/download/v0.40.0/conftest_0.40.0_Linux_x86_64.tar.gz'
        sh 'tar xzf conftest_0.40.0_Linux_x86_64.tar.gz'
      }
    }
    
    stage('Policy Check') {
      steps {
        sh './conftest test -p policy/ manifests/'
      }
    }
  }
}
```

---

## 🔐 Security Best Practices

### Current Security Posture

✅ **Implemented**:
- Latest LTS version (2.516.3) with Java 21
- CSRF protection enabled
- No executors on controller (agents only)
- Secrets in Azure Key Vault (never in git)
- TLS certificate from Let's Encrypt
- RBAC enabled (Kubernetes service account)
- Prometheus metrics for monitoring

⚠️ **Consider for Production**:
- Matrix-based authorization (replace `loggedInUsersCanDoAnything`)
- Audit logging enabled
- Build timeout limits (prevent runaway jobs)
- Resource quotas on jenkins namespace
- Network policies (isolate Jenkins network)
- Regular plugin updates (monthly)

### Hardening Checklist

```yaml
# jenkins-values.yaml additions for production:
controller:
  JCasC:
    configScripts:
      security-hardening: |
        jenkins:
          authorizationStrategy:
            projectMatrix:
              permissions:
                - "Overall/Read:authenticated"
                - "Overall/Administer:admin"
                - "Job/Build:authenticated"
                - "Job/Cancel:authenticated"
          
        security:
          globalJobDslSecurityConfiguration:
            useScriptSecurity: true
          
        unclassified:
          buildDiscarders:
            configuredBuildDiscarders:
              - "jobBuildDiscarder"
              - defaultBuildDiscarder:
                  discarder:
                    logRotator:
                      numToKeepStr: "10"
                      artifactNumToKeepStr: "5"
```

---

## 🔄 Enabling Applies (Optional)

To enable `terraform apply` or `kubectl apply` in Jenkins:

### 1. Update RBAC

Grant Jenkins service account permissions:

```bash
# Create RBAC for kubectl access (if needed)
kubectl create clusterrolebinding jenkins-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=jenkins:jenkins
```

### 2. Update JCasC Configuration

Edit `jenkins-values.yaml`:

```yaml
controller:
  JCasC:
    configScripts:
      apply-jobs: |
        jobs:
          - script: >
              pipelineJob('terraform-apply') {
                definition {
                  cpsScm {
                    scm {
                      git {
                        remote { url('https://github.com/Canepro/rocketchat-k8s.git') }
                        branch('*/main')
                      }
                    }
                    scriptPath('jenkins/terraform-apply.Jenkinsfile')
                  }
                }
                triggers {
                  cron('@daily')  # Daily apply check
                }
              }
```

### 3. Add Azure CLI to Terraform Agent

Update `jenkins-values.yaml`:

```yaml
agent:
  podTemplates:
    terraform: |
      - name: terraform
        label: terraform
        containers:
          - name: terraform
            image: mcr.microsoft.com/azure-cli:latest  # Use Azure CLI image with Terraform
            command: "/bin/sh -c"
            args: "cat"
            ttyEnabled: true
```

**Note**: This makes Jenkins capable of managing multiple projects' infrastructure, not just RocketChat K8s.

### 4. Configure Azure Workload Identity (for terraform apply)

Update service account annotations:

```yaml
controller:
  serviceAccount:
    annotations:
      azure.workload.identity/client-id: "UAMI_CLIENT_ID"  # ESO identity client ID
      azure.workload.identity/tenant-id: "c3d431f1-3e02-4c62-a825-79cd8f9e2053"
```

---

## 📊 Monitoring

### Prometheus Metrics

Jenkins exposes Prometheus metrics at `http://jenkins:8080/prometheus`:

```yaml
# Example ServiceMonitor (already created by Helm chart)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: jenkins
  namespace: jenkins
spec:
  selector:
    matchLabels:
      app: jenkins
  endpoints:
    - port: http
      path: /prometheus
      interval: 30s
```

**Key Metrics**:
- `jenkins_node_count_value` - Number of agents
- `jenkins_job_duration_milliseconds_summary` - Job duration
- `jenkins_queue_size_value` - Build queue size
- `jenkins_executor_count_value` - Executor count

### Health Checks

```bash
# Check Jenkins health
kubectl exec -n jenkins jenkins-0 -c jenkins -- \
  curl -s http://localhost:8080/login

# Check pod logs
kubectl logs -n jenkins jenkins-0 -c jenkins --tail=50

# Check events
kubectl get events -n jenkins --sort-by='.lastTimestamp'
```

---

## 🔍 Troubleshooting

### Common Issues

#### 1. Pod Stuck in "Pending"

```bash
# Check events
kubectl describe pod -n jenkins jenkins-0

# Common causes:
# - PVC not bound (check: kubectl get pvc -n jenkins)
# - Resource constraints (check node capacity)
```

#### 2. TLS Certificate Not Issuing

```bash
# Check certificate status
kubectl describe certificate jenkins-tls -n jenkins

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check ACME challenge
kubectl get challenges -A
```

#### 3. External Secrets Not Syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret -n jenkins
kubectl describe externalsecret jenkins-admin -n jenkins

# Check ClusterSecretStore
kubectl get clustersecretstore azure-keyvault
kubectl describe clustersecretstore azure-keyvault

# Check ESO controller logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

#### 4. GitHub Webhook Not Working

```bash
# Check Jenkins GitHub configuration
# Jenkins → Manage Jenkins → Configure System → GitHub

# Verify webhook URL: https://jenkins.canepro.me/github-webhook/

# Check firewall rules (GitHub IPs must reach LoadBalancer)
# Azure Portal → Network Security Group → Inbound rules
```

#### 5. Agent Pods Not Starting

```bash
# Check Jenkins logs for agent errors
kubectl logs -n jenkins jenkins-0 -c jenkins | grep -i "agent\|kubernetes"

# Check RBAC permissions
kubectl auth can-i create pods --as=system:serviceaccount:jenkins:jenkins -n jenkins

# Check Kubernetes plugin configuration
# Jenkins → Manage Jenkins → Configure Clouds → Kubernetes
```

### Debug Commands

```bash
# Full Jenkins logs
kubectl logs -n jenkins jenkins-0 -c jenkins --tail=100 -f

# Shell into Jenkins pod
kubectl exec -n jenkins jenkins-0 -c jenkins -it -- bash

# Check Java version
kubectl exec -n jenkins jenkins-0 -c jenkins -- java -version

# Check installed plugins
kubectl exec -n jenkins jenkins-0 -c jenkins -- ls /var/jenkins_home/plugins/

# Restart Jenkins (graceful)
kubectl rollout restart statefulset jenkins -n jenkins
```

---

## 🔄 Upgrade Procedure

### Upgrading Jenkins

1. **Check for updates**:
   - Helm chart: [Jenkins Helm Releases](https://github.com/jenkinsci/helm-charts/releases)
   - Jenkins LTS: [Jenkins Changelog](https://www.jenkins.io/changelog-stable/)

2. **Update version files**:
   ```bash
   # Update GrafanaLocal/argocd/applications/aks-jenkins.yaml
   # Change: targetRevision: 5.8.110
   # To:     targetRevision: 5.x.x  (new version)
   
   # Update jenkins-values.yaml
   # Change: tag: "2.516.3-lts-jdk21"
   # To:     tag: "2.xxx.x-lts-jdk21"  (new version)
   
   # Update VERSIONS.md
   # Update version and date in CI/CD Stack table
   ```

3. **Commit and push**:
   ```bash
   git add GrafanaLocal/argocd/applications/aks-jenkins.yaml jenkins-values.yaml VERSIONS.md
   git commit -m "chore: Upgrade Jenkins to 2.xxx.x + chart 5.x.x"
   git push
   ```

4. **Monitor ArgoCD sync**:
   ```bash
   kubectl get application -n argocd aks-jenkins -w
   ```

5. **Verify upgrade**:
   ```bash
   # Check Jenkins version
   kubectl exec -n jenkins jenkins-0 -c jenkins -- \
     cat /var/jenkins_home/jenkins.version
   
   # Check UI: https://jenkins.canepro.me/manage
   ```

---

## 📚 Additional Resources

- [Jenkins Official Documentation](https://www.jenkins.io/doc/)
- [Jenkins Configuration as Code (JCasC)](https://github.com/jenkinsci/configuration-as-code-plugin)
- [Jenkins Kubernetes Plugin](https://plugins.jenkins.io/kubernetes/)
- [Jenkins Helm Chart Documentation](https://github.com/jenkinsci/helm-charts/tree/main/charts/jenkins)
- [Jenkins Best Practices](https://www.jenkins.io/doc/book/pipeline/pipeline-best-practices/)

---

## 📝 Summary

**Deployment Time**: ~5 minutes (including TLS certificate)

**Resources Used**:
- CPU: 500m request, 2000m limit
- Memory: 1Gi request, 4Gi limit
- Storage: 20Gi persistent volume
- Network: LoadBalancer (shared with Traefik)

**What You Get**:
- ✅ Latest Jenkins LTS (2.516.3) with Java 21
- ✅ Secure by default (CSRF, RBAC, TLS)
- ✅ Dynamic Kubernetes agents (3 types)
- ✅ GitHub integration ready
- ✅ Prometheus metrics enabled
- ✅ Automatic backups via persistent volume
- ✅ GitOps managed via ArgoCD

**Next Steps**:
1. Create GitHub webhooks for PR validation
2. Add Jenkinsfile to your repositories
3. Configure matrix-based authorization (production)
4. Set up backup schedule (recommended)
5. Enable applies if needed (optional)

Good luck with Jenkins! 🚀
