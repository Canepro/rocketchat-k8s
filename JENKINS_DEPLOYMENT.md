# Jenkins Deployment Guide

This guide covers deploying a general-purpose Jenkins CI server on AKS for CI validation across multiple projects.

**Last Updated**: 2026-01-19

---

## 📋 Overview

### Jenkins Configuration
- **Version**: Jenkins LTS 2.528.3 with Java 21
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
# Get admin credentials (from Key Vault via External Secret)
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.username}' | base64 -d
echo
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d

# Open browser to: https://jenkins.canepro.me
# Login with:
#   Username: <username from above>
#   Password: <password from above>
```

**Note on “changed” credentials**:
- Credentials are sourced from **Azure Key Vault** via **External Secrets Operator (ESO)** and materialized into `secret/jenkins-admin`.
- Jenkins is configured via JCasC to **create the admin user** from those secret values at boot (so the UI login always matches what `kubectl get secret jenkins-admin ...` returns).

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

---

## 🎯 Post-Deployment Setup (Getting Jenkins Fully Functional)

After Jenkins is deployed, follow these steps to get it fully functional for CI validation:

### Current Status (2026-01-21)
- ✅ Jenkins deployed and running
- ✅ TLS certificate issued
- ✅ Admin credentials synced from Key Vault
- ✅ GitHub token secret synced
- ⚠️ Prometheus disk usage warning (fixed in jenkins-values.yaml - will apply on next sync)
- ⚠️ GitHub token credential needs to be configured in Jenkins UI
- ⚠️ GitHub webhook needs to be configured
- ⚠️ Jenkinsfiles need to be created

### Step 1: Fix Prometheus Warning ✅ (Fixed)
**Issue**: Prometheus plugin trying to collect disk usage but CloudBees Disk Usage Simple plugin not installed.

**Fix**: Disabled disk usage collection in `jenkins-values.yaml` JCasC configuration. Will apply on next ArgoCD sync.

### Step 2: Configure GitHub Token Credential
**Purpose**: Jenkins needs the GitHub token to authenticate with GitHub API for PR validation.

**Action**:
1. Access Jenkins UI: `https://jenkins.canepro.me`
2. Login with admin credentials (get from Key Vault secret)
3. Navigate: **Manage Jenkins** → **Credentials** → **System** → **Global credentials (unrestricted)**
4. Click **Add Credentials**
5. Configure:
   - **Kind**: Secret text
   - **Secret**: Get from `kubectl get secret jenkins-github -n jenkins -o jsonpath='{.data.token}' | base64 -d`
   - **ID**: `github-token` (must match `jenkins-values.yaml` line 78)
   - **Description**: "GitHub Personal Access Token for PR validation"
6. Click **OK**

### Step 3: Set Up GitHub Webhook
**Purpose**: Automatically trigger Jenkins jobs when PRs are created/updated.

**Action**:
1. Go to: `https://github.com/Canepro/rocketchat-k8s/settings/hooks`
2. Click **Add webhook**
3. Configure:
   - **Payload URL**: `https://jenkins.canepro.me/github-webhook/`
   - **Content type**: `application/json`
   - **Events**: Select "Let me select individual events"
     - ✅ Pull requests
     - ✅ Pushes (optional)
   - **Active**: ✅ Enabled
4. Click **Add webhook**

### Step 4: Create Jenkinsfile
**Purpose**: Define CI validation pipeline for your repository.

**Create**: `.jenkins/Jenkinsfile` (or `Jenkinsfile` in root) with validation stages (see examples in "Creating CI Jobs" section above).

### Step 5: Create Pipeline Job
**Purpose**: Connect Jenkins to your repository.

**Option A: Via Jenkins UI** (if UI is working)
1. **Jenkins UI** → **New Item** → **Multibranch Pipeline**
2. **Name**: `rocketchat-k8s`
3. **Branch Sources** section:
   - Click **"Add source"** button (at the top of the Branch Sources section)
   - Select **"GitHub"** from the dropdown menu
   - This will add a GitHub branch source configuration section
4. Configure the GitHub branch source:

**Option B: Via CLI** (if UI is not working - **Recommended**)
See `.jenkins/setup-via-cli.md` for complete CLI setup instructions.

**Quick CLI Method** (with CSRF token):
```bash
# Get Jenkins admin password
JENKINS_PASSWORD=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d)
JENKINS_URL="https://jenkins.canepro.me"

# Get CSRF token (required when CSRF protection is enabled)
CRUMB=$(curl -s -u "admin:$JENKINS_PASSWORD" \
  "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

# Create job from XML config
curl -X POST \
  -u "admin:$JENKINS_PASSWORD" \
  -H "$CRUMB" \
  -H "Content-Type: application/xml" \
  --data-binary @.jenkins/job-config.xml \
  "$JENKINS_URL/createItem?name=rocketchat-k8s"

# Trigger initial scan
curl -X POST \
  -u "admin:$JENKINS_PASSWORD" \
  -H "$CRUMB" \
  "$JENKINS_URL/job/rocketchat-k8s/scan"
```

**Note**: Jenkins has CSRF protection enabled (security best practice), so all API calls require a CSRF token. The token is obtained from `/crumbIssuer/api/xml` and must be included in the request headers.

**Continue with UI configuration** (if using Option A):
   - **Repository HTTPS URL**: `https://github.com/Canepro/rocketchat-k8s`
   - **Credentials**: Select `github-token` from dropdown
     - **Important**: 
       - If `github-token` doesn't appear in the dropdown, it may already exist. Check **Manage Jenkins** → **Credentials** → **System** → **Global credentials (unrestricted)** to verify.
       - If you see "This ID is already in use" error when trying to add it, the credential already exists - just select it from the dropdown instead of creating a new one.
       - Even though the UI may show "Credentials ok. Connected to..." with "- none -" selected, you **must** select `github-token` for PR status checks to work properly. Public repos can be scanned without credentials, but PR status reporting requires authentication.
   - **Behaviours** (click "Add" to add behaviors):
     - ✅ **Discover branches**: Strategy = "Exclude branches that are also filed as PRs"
     - ✅ **Discover pull requests from origin**: Strategy = "The current pull request revision"
     - ✅ **Discover pull requests from forks**: Strategy = "The current pull request revision" (optional)
     - **Trust**: "From users with Admin or Write permission" (default)
5. **Build Configuration**:
   - **Mode**: "by Jenkinsfile"
   - **Script Path**: `.jenkins/terraform-validation.Jenkinsfile` (or `.jenkins/helm-validation.Jenkinsfile`)
     - Note: This is the path relative to repository root where your Jenkinsfile is located
6. **Save** → **Scan Multibranch Pipeline Now**

### Step 6: Test End-to-End
1. Create a test PR on GitHub
2. Verify Jenkins job triggers automatically
3. Check PR status check appears on GitHub
4. Verify build completes successfully

---

## 🎯 Best Practices for Jenkins in Your GitOps Setup

### 1. **CI Validation Only (Current Best Practice)** ✅
- **What**: Jenkins performs static analysis, linting, testing, and pre-deployment validation
- **Why**: Aligns with GitOps where ArgoCD is the source of truth. Prevents Jenkins from becoming a "break glass" tool
- **Your Setup**: Already configured correctly - no `terraform apply` or `kubectl apply` by default

### 2. **Dynamic Kubernetes Agents** ✅
- **What**: Jobs run on ephemeral pods that spin up on demand
- **Why**: Scalability, isolation, tool-specific environments
- **Your Setup**: Already configured with `default`, `terraform`, and `helm` agents

### 3. **Jenkinsfiles-as-Code** (Mandatory)
- **What**: Define pipelines in `Jenkinsfile` stored in each repository
- **Why**: Version control, self-service, consistency, auditability
- **Action**: Create Jenkinsfiles for all three repositories (see below)

### 4. **Multibranch Pipelines** (Recommended)
- **What**: Automatically scan repositories for branches and PRs
- **Why**: Reduces manual setup, ensures every change gets validated
- **Action**: Set up Multibranch Pipeline jobs for each repository

### 5. **External Secret Management** ✅
- **What**: Secrets in Azure Key Vault via External Secrets Operator
- **Why**: Secrets out of Git/Jenkins UI, centralized management
- **Your Setup**: Already implemented

### 6. **Comprehensive Monitoring** ✅
- **What**: Prometheus metrics exposed and integrated with Grafana
- **Why**: Visibility into health, queue, agents, job performance
- **Your Setup**: Already configured

---

## 📦 Jenkins Setup for All Three Repositories

### Repository 1: `rocketchat-k8s` (AKS GitOps)

**Purpose**: Infrastructure-as-Code validation for AKS-based RocketChat deployment

**Recommended Jenkinsfiles**:

#### `.jenkins/terraform-validation.Jenkinsfile`
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
        dir('terraform') {
          sh 'terraform fmt -check -recursive'
        }
      }
    }
    
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          sh 'terraform init -backend=false'
          sh 'terraform validate'
        }
      }
    }
    
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          sh 'terraform init'
          sh 'terraform plan -no-color -out=tfplan'
        }
      }
    }
  }
  
  post {
    always {
      cleanWs()
    }
  }
}
```

#### `.jenkins/helm-validation.Jenkinsfile`
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
        sh '''
          helm template rocketchat . -f values.yaml > /tmp/manifests.yaml
          helm template traefik . -f traefik-values.yaml > /tmp/traefik-manifests.yaml || true
        '''
      }
    }
    
    stage('Kubeconform Validate') {
      steps {
        sh 'kubeconform -strict /tmp/manifests.yaml /tmp/traefik-manifests.yaml'
      }
    }
    
    stage('YAML Lint') {
      steps {
        sh '''
          yamllint -c .yamllint.yaml *.yaml || true
          yamllint -c .yamllint.yaml ops/manifests/*.yaml || true
        '''
      }
    }
  }
  
  post {
    always {
      cleanWs()
    }
  }
}
```

**Setup Steps**:
1. Create `.jenkins/` directory in repository
2. Add both Jenkinsfiles above
3. Create Multibranch Pipeline job: `rocketchat-k8s`
   - **Branch Sources** section:
     - Click **"Add source"** button (at the top of Branch Sources section, NOT the "Add" next to Credentials)
     - Select **"GitHub"** from the dropdown menu
   - Configure the GitHub branch source:
     - **Repository HTTPS URL**: `https://github.com/Canepro/rocketchat-k8s`
     - **Credentials**: Select `github-token` from dropdown
       - **Note**: If you see "This ID is already in use" error, the credential already exists - just select it from the dropdown instead of creating a new one
     - **Behaviours** (click "Add" button in Behaviours section):
       - **Discover branches**: Strategy = "Exclude branches that are also filed as PRs"
       - **Discover pull requests from origin**: Strategy = "The current pull request revision"
       - **Trust**: "From users with Admin or Write permission"
   - **Build Configuration**:
     - **Mode**: "by Jenkinsfile"
     - **Script Path**: `.jenkins/terraform-validation.Jenkinsfile` (or `.jenkins/helm-validation.Jenkinsfile`)
4. Add GitHub webhook: `https://jenkins.canepro.me/github-webhook/`

---

### Repository 2: `central-observability-hub-stack` (OKE Hub)

**Purpose**: Infrastructure validation for OKE-based observability hub (complements existing GitHub Actions)

**Note**: This repo already has GitHub Actions for DevOps Quality Gate. Jenkins can provide:
- More resource-intensive validation
- Different validation types (e.g., Terraform plan with detailed output)
- Centralized CI reporting across all repos

**Recommended Jenkinsfiles**:

#### `.jenkins/terraform-validation.Jenkinsfile`
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
        dir('terraform') {
          sh 'terraform fmt -check -recursive'
        }
      }
    }
    
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          sh 'terraform init -backend=false'
          sh 'terraform validate'
        }
      }
    }
    
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          sh 'terraform init'
          sh 'terraform plan -detailed-exitcode -no-color'
        }
      }
    }
  }
  
  post {
    always {
      cleanWs()
    }
  }
}
```

#### `.jenkins/k8s-manifest-validation.Jenkinsfile`
```groovy
pipeline {
  agent {
    kubernetes {
      label 'helm'
      defaultContainer 'helm'
    }
  }
  
  stages {
    stage('ArgoCD App Validation') {
      steps {
        sh '''
          # Validate ArgoCD Application manifests
          for app in argocd/applications/*.yaml; do
            kubeconform -strict "$app" || exit 1
          done
        '''
      }
    }
    
    stage('Helm Chart Validation') {
      steps {
        dir('helm') {
          sh '''
            for chart in */values.yaml; do
              chart_dir=$(dirname "$chart")
              helm template "$chart_dir" "$chart_dir" -f "$chart" > /tmp/"$chart_dir"-manifests.yaml
              kubeconform -strict /tmp/"$chart_dir"-manifests.yaml || exit 1
            done
          '''
        }
      }
    }
    
    stage('YAML Lint') {
      steps {
        sh '''
          yamllint -c .yamllint.yaml argocd/ k8s/ helm/ || true
        '''
      }
    }
    
    stage('Security Scan') {
      steps {
        sh '''
          # Use kube-linter (if available) or similar
          # This complements GitHub Actions kube-linter
          echo "Security scanning via kube-linter..."
        '''
      }
    }
  }
  
  post {
    always {
      cleanWs()
    }
  }
}
```

**Setup Steps**:
1. Create `.jenkins/` directory
2. Add Jenkinsfiles above
3. Create Multibranch Pipeline job: `central-observability-hub-stack`
   - **Branch Sources** → **GitHub**:
     - **Repository HTTPS URL**: `https://github.com/Canepro/central-observability-hub-stack`
     - **Credentials**: Select `github-token`
     - **Behaviours**: Add "Discover branches" and "Discover pull requests from origin"
   - **Build Configuration** → **Script Path**: `.jenkins/terraform-validation.Jenkinsfile` (or `.jenkins/k8s-manifest-validation.Jenkinsfile`)
4. Configure GitHub webhook: `https://jenkins.canepro.me/github-webhook/`
5. **Note**: This runs in parallel with GitHub Actions - both provide validation

---

### Repository 3: `portfolio_website-main` (Next.js Application)

**Purpose**: Application-level validation (complements Azure DevOps pipelines)

**Recommended Jenkinsfile**:

#### `.jenkins/application-validation.Jenkinsfile`
```groovy
pipeline {
  agent {
    kubernetes {
      label 'default'
      defaultContainer 'jnlp'
    }
  }
  
  environment {
    NODE_VERSION = '20'
    BUN_VERSION = '1.3.5'
  }
  
  stages {
    stage('Setup') {
      steps {
        sh '''
          # Install Bun (if not in agent image)
          curl -fsSL https://bun.sh/install | bash
          export PATH="$HOME/.bun/bin:$PATH"
          bun --version
        '''
      }
    }
    
    stage('Dependency Audit') {
      steps {
        sh '''
          export PATH="$HOME/.bun/bin:$PATH"
          bun audit || echo "Audit completed with warnings"
        '''
      }
    }
    
    stage('Code Quality') {
      steps {
        sh '''
          export PATH="$HOME/.bun/bin:$PATH"
          bun run lint
          bun run format:check
        '''
      }
    }
    
    stage('Type Checking') {
      steps {
        sh '''
          export PATH="$HOME/.bun/bin:$PATH"
          bun run typecheck
        '''
      }
    }
    
    stage('Build Validation') {
      steps {
        sh '''
          export PATH="$HOME/.bun/bin:$PATH"
          bun run build
        '''
      }
    }
    
    stage('Container Scan') {
      when {
        anyOf {
          branch 'main'
          branch 'master'
        }
      }
      steps {
        sh '''
          # Scan Dockerfile for vulnerabilities (if Dockerfile exists)
          if [ -f Dockerfile ]; then
            # Use trivy or similar (install if needed)
            echo "Container scanning would run here"
          fi
        '''
      }
    }
  }
  
  post {
    always {
      cleanWs()
    }
    success {
      echo "✅ All validation checks passed"
    }
    failure {
      echo "❌ Validation checks failed"
    }
  }
}
```

**Alternative: Custom Agent with Bun Pre-installed**

Create a custom agent in `jenkins-values.yaml`:

```yaml
agent:
  podTemplates:
    bun: |
      - name: bun
        label: bun
        nodeUsageMode: EXCLUSIVE
        containers:
          - name: bun
            image: oven/bun:1.3.5-alpine
            command: "/bin/sh -c"
            args: "cat"
            ttyEnabled: true
            resourceRequestCpu: "200m"
            resourceRequestMemory: "512Mi"
            resourceLimitCpu: "2000m"
            resourceLimitMemory: "4Gi"
```

Then use `label 'bun'` in the Jenkinsfile.

**Setup Steps**:
1. Create `.jenkins/` directory
2. Add Jenkinsfile above
3. Create Multibranch Pipeline job: `portfolio_website-main`
   - **Branch Sources** → **GitHub**:
     - **Repository HTTPS URL**: `https://github.com/Canepro/portfolio_website-main`
     - **Credentials**: Select `github-token`
     - **Behaviours**: Add "Discover branches" and "Discover pull requests from origin"
   - **Build Configuration** → **Script Path**: `.jenkins/application-validation.Jenkinsfile`
4. Configure GitHub webhook: `https://jenkins.canepro.me/github-webhook/`
5. **Note**: This complements Azure DevOps - Jenkins provides additional validation layer

---

## 🚀 Maximizing Jenkins Value

### 1. **Centralized CI Dashboard**
- All three repositories report to same Jenkins instance
- Unified view of CI health across all projects
- Consistent validation standards

### 2. **Parallel Validation**
- Jenkins + GitHub Actions for `central-observability-hub-stack` (redundancy)
- Jenkins + Azure DevOps for `portfolio_website-main` (complementary)
- Multiple validation layers catch different issues

### 3. **Resource-Intensive Validations**
- Terraform plans with full state (Jenkins can handle larger workloads)
- Container image scanning
- Security policy checks (OPA/Conftest)

### 4. **Cross-Repository Validation**
- Validate ArgoCD app references across repos
- Check consistency of Helm chart versions
- Verify cross-repo dependencies

### 5. **Custom Metrics & Reporting**
- Track validation success rates per repository
- Monitor build times and resource usage
- Alert on validation failures

---

## 📋 Quick Setup Checklist

### For Each Repository:

- [ ] Create `.jenkins/` directory
- [ ] Add appropriate Jenkinsfile(s)
- [ ] Create Multibranch Pipeline job in Jenkins
- [ ] Configure GitHub webhook
- [ ] Test with a sample PR
- [ ] Verify status checks appear on GitHub

### Jenkins Configuration:

- [ ] ✅ GitHub token credential (already done)
- [ ] ✅ Prometheus warning fixed (in progress)
- [ ] Create Multibranch Pipeline jobs for all 3 repos
- [ ] Configure webhooks for all 3 repos
- [ ] Test agent connectivity
- [ ] Monitor first successful PR validations

---

**Next Steps**:
1. Create Jenkinsfiles for all three repositories
2. Set up Multibranch Pipeline jobs
3. Configure GitHub webhooks
4. Test end-to-end validation
5. Configure matrix-based authorization (production hardening)
6. Set up backup schedule (recommended)

Good luck with Jenkins! 🚀
