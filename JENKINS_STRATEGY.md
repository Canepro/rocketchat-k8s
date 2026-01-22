# Jenkins Strategy & Maximization Guide

**Purpose**: Understanding what Jenkins does, why it's valuable, and how to maximize it across all your repositories and clusters.

---

## 🎯 What We Set Up

### The Big Picture: CI vs CD Separation

Your architecture uses a **split CI/CD model**:

```
┌─────────────────────────────────────────────────────────┐
│                    CI (Continuous Integration)          │
│  GitHub PR → Jenkins → Validation → PR Status Check     │
│  ✅ Catches errors BEFORE code reaches master            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                    CD (Continuous Deployment)            │
│  master branch → ArgoCD → Auto-sync → Cluster            │
│  ✅ Deploys validated code automatically                 │
└─────────────────────────────────────────────────────────┘
```

**Why split them?**
- **Jenkins (CI)**: Fast feedback loop, catches mistakes early, doesn't need cluster access
- **ArgoCD (CD)**: GitOps deployment, declarative, cluster-native, handles rollbacks

### What Jenkins Actually Does

Jenkins is your **quality gate** that runs **before** code merges to `master`:

1. **Terraform Validation** (`terraform-validation.Jenkinsfile`):
   - ✅ Format check (`terraform fmt -check`) - ensures consistent code style
   - ✅ Syntax validation (`terraform validate`) - catches typos and errors
   - ✅ Plan generation (`terraform plan`) - shows what would change (read-only)

2. **Helm/Kubernetes Validation** (`helm-validation.Jenkinsfile`):
   - ✅ Helm template rendering - validates Helm syntax
   - ✅ Kubeconform validation - checks Kubernetes API schema compliance
   - ✅ YAML linting - catches formatting issues

3. **Automatic PR Discovery**:
   - Jenkins watches your GitHub repo
   - When you create a PR, it automatically:
     - Checks out your branch
     - Runs validation pipelines
     - Reports pass/fail status back to GitHub PR
   - You see ✅ or ❌ directly in the PR

4. **Dynamic Kubernetes Agents**:
   - Jenkins doesn't run jobs on the main Jenkins pod
   - Instead, it creates temporary pods in your cluster with the right tools:
     - `terraform` agent = Hashicorp Terraform image
     - `helm` agent = Alpine with Helm, kubectl, kubeconform
   - After the job finishes, the pod is deleted (cost-efficient)

---

## 💡 Why This Is Valuable

### Problem It Solves

**Without Jenkins:**
```
Developer creates PR → Merge to master → ArgoCD syncs → 
❌ Terraform syntax error → Cluster deployment fails → 
❌ RocketChat down → Emergency rollback needed
```

**With Jenkins:**
```
Developer creates PR → Jenkins validates → ❌ Terraform error found → 
PR shows ❌ status → Developer fixes → Jenkins validates again → 
✅ All checks pass → Merge to master → ArgoCD syncs → ✅ Success
```

### Real Benefits

1. **Catch Errors Early**: Syntax errors, typos, and invalid configs are caught before they reach production
2. **Faster Feedback**: See validation results in 2-3 minutes instead of waiting for ArgoCD sync + deployment
3. **Prevent Broken Deployments**: Invalid Terraform/Helm won't break your cluster
4. **Team Confidence**: Everyone can see PR validation status before merging
5. **Documentation**: Jenkins logs show exactly what failed and why

### Cost Efficiency

- **Dynamic agents**: Only create pods when needed, delete after job completes
- **No idle resources**: Unlike a dedicated CI server, you only pay for compute during builds
- **Shared infrastructure**: One Jenkins instance validates all repos

---

## 🚀 How to Maximize Jenkins

### Current Setup (rocketchat-k8s)

✅ **What's Working:**
- Multibranch Pipeline job: `rocketchat-k8s`
- Auto-discovers branches and PRs
- Runs Terraform + Helm validation
- Reports status to GitHub PRs
- Webhook configured for instant triggers

### Extending to Other Repositories

You mentioned 3 main repos:
1. `rocketchat-k8s` ✅ (already set up)
2. `central-observability-hub-stack` (on OKE cluster)
3. `portfolio_website-main`

#### Strategy 1: Same Jenkins, Different Clusters

**For `central-observability-hub-stack` (OKE cluster):**

1. **Create Jenkinsfile in that repo**:
   ```groovy
   // .jenkins/terraform-validation.Jenkinsfile
   pipeline {
     agent {
       kubernetes {
         label 'terraform'
         defaultContainer 'terraform'
       }
     }
     stages {
       stage('Terraform Validate') {
         steps {
           dir('terraform') {
             sh 'terraform fmt -check -recursive'
             sh 'terraform init -backend=false'
             sh 'terraform validate'
           }
         }
       }
     }
   }
   ```

2. **Create Jenkins job** (same process):
   ```bash
   # In rocketchat-k8s repo (or create a shared script)
   bash .jenkins/create-job.sh
   # When prompted:
   # Job name: central-observability-hub-stack
   # Repo URL: https://github.com/Canepro/central-observability-hub-stack
   # Jenkinsfile path: .jenkins/terraform-validation.Jenkinsfile
   ```

3. **Configure webhook** in `central-observability-hub-stack` repo:
   - URL: `https://jenkins.canepro.me/github-webhook/`
   - Events: Pull requests, Pushes

**Note**: Jenkins runs on AKS, but it can validate code for OKE repos. The validation doesn't need cluster access (it's just syntax checking).

#### Strategy 2: Multi-Cluster Jenkins (Advanced)

If you want Jenkins to also **deploy** to OKE (not just validate), you'd need:

1. **Kubernetes credentials in Jenkins** for OKE cluster:
   - Add OKE kubeconfig as a Jenkins credential
   - Configure Jenkins agents to use OKE context for deployment jobs

2. **Separate deployment pipelines** (optional):
   ```groovy
   // .jenkins/deploy-to-oke.Jenkinsfile
   pipeline {
     agent { kubernetes { label 'kubectl' } }
     stages {
       stage('Deploy to OKE') {
         steps {
           sh 'kubectl --context oke-cluster apply -f manifests/'
         }
       }
     }
   }
   ```

**Recommendation**: Keep validation-only for now. Use ArgoCD on OKE for deployments (GitOps pattern).

#### Strategy 3: Portfolio Website

For `portfolio_website-main`:

1. **Create appropriate Jenkinsfile**:
   - If it's a static site: HTML/CSS linting, build validation
   - If it uses a framework: npm/yarn build, test, lint
   - Example:
   ```groovy
   pipeline {
     agent { kubernetes { label 'node' } }
     stages {
       stage('Build') {
         steps {
           sh 'npm install'
           sh 'npm run build'
         }
       }
       stage('Lint') {
         steps {
           sh 'npm run lint'
         }
       }
     }
   }
   ```

2. **Create Jenkins job** (same as above)

3. **Configure webhook**

### Maximization Best Practices

#### 1. Standardize Jenkinsfile Patterns

Create a **shared Jenkinsfile library** or templates:

```
.jenkins/
├── templates/
│   ├── terraform-validation.groovy
│   ├── helm-validation.groovy
│   ├── nodejs-build.groovy
│   └── python-build.groovy
```

Then in each repo, use a minimal Jenkinsfile that imports the template:
```groovy
@Library('jenkins-shared-library') _
terraformValidationPipeline()
```

#### 2. Reusable Kubernetes Agent Pod Templates

Define common agent types in Jenkins configuration:

```yaml
# In jenkins-values.yaml (JCasC)
jenkins:
  clouds:
    - kubernetes:
        templates:
          - name: terraform
            label: terraform
            containers:
              - name: terraform
                image: hashicorp/terraform:latest
          - name: helm
            label: helm
            containers:
              - name: helm
                image: alpine/helm:latest
          - name: node
            label: node
            containers:
              - name: node
                image: node:20-alpine
```

#### 3. Shared Credentials

Store common credentials (GitHub tokens, Docker registry, etc.) in:
- Azure Key Vault → External Secrets Operator → Jenkins credentials

#### 4. Pipeline as Code

**Always** store Jenkinsfiles in the repo (not in Jenkins UI):
- ✅ Version controlled
- ✅ Reviewable in PRs
- ✅ Reproducible
- ✅ Self-documenting

#### 5. Notification Strategy

Configure Jenkins to notify on failures:
- GitHub PR comments
- Slack/Discord webhooks (optional)
- Email (optional, but can be noisy)

---

## 🔄 Workflow Examples

### Example 1: Terraform Change

```
1. Developer creates feature branch: git checkout -b add-new-vm
2. Edits terraform/vm.tf
3. Commits: git commit -m "Add new VM"
4. Pushes: git push origin add-new-vm
5. Creates PR on GitHub
6. GitHub webhook triggers Jenkins
7. Jenkins:
   - Checks out PR branch
   - Runs terraform fmt -check → ❌ Fails (missing newline)
   - Reports ❌ to GitHub PR
8. Developer sees ❌ in PR, fixes formatting
9. Pushes fix
10. Jenkins runs again → ✅ Passes
11. Developer merges PR
12. ArgoCD detects master change → Syncs → Deploys
```

### Example 2: Helm Chart Update

```
1. Developer updates values.yaml (RocketChat version)
2. Creates PR
3. Jenkins:
   - Runs helm template → ✅ Renders successfully
   - Runs kubeconform → ❌ Fails (API version deprecated)
   - Reports ❌ to GitHub PR
4. Developer updates API version
5. Jenkins runs again → ✅ Passes
6. Merge → ArgoCD syncs → Rolling update
```

---

## 📊 Monitoring & Metrics

Jenkins exposes Prometheus metrics at `/prometheus`:

- Build success/failure rates
- Build duration
- Queue wait times
- Agent utilization

**View in Grafana**: Create a dashboard using Jenkins Prometheus plugin metrics.

---

## 🎓 Key Takeaways

1. **Jenkins = Quality Gate**: Catches errors before they reach production
2. **CI vs CD Split**: Jenkins validates, ArgoCD deploys (best practice)
3. **One Jenkins, Many Repos**: Same instance can validate all your repos
4. **Dynamic Agents**: Cost-efficient, only runs when needed
5. **Pipeline as Code**: Jenkinsfiles live in repos, not Jenkins UI
6. **Extensible**: Easy to add new repos, new validation types, new clusters

---

## 🚦 Next Steps

### Immediate (When Cluster is Back)

1. **Test the current setup**:
   - Create a test PR in `rocketchat-k8s`
   - Verify Jenkins auto-discovers and builds
   - Check PR status shows ✅ or ❌

2. **Verify webhook**:
   - Check Jenkins logs: `kubectl logs -n jenkins jenkins-0 -f`
   - Create PR → Should see webhook trigger in logs

### Short Term (This Week)

1. **Add second repo** (`central-observability-hub-stack`):
   - Create Jenkinsfile in that repo
   - Create Jenkins job
   - Configure webhook

2. **Standardize patterns**:
   - Document Jenkinsfile templates
   - Create shared agent definitions

### Long Term (This Month)

1. **Add third repo** (`portfolio_website-main`)
2. **Set up notifications** (Slack/Discord optional)
3. **Create Grafana dashboard** for Jenkins metrics
4. **Consider Jenkins Shared Library** for advanced reuse

---

## ❓ Common Questions

**Q: Can Jenkins deploy to the cluster?**  
A: Yes, but we keep it validation-only. ArgoCD handles deployments (GitOps best practice).

**Q: What if I want Jenkins to deploy?**  
A: Add `kubectl apply` stages to Jenkinsfiles, but this breaks GitOps. Not recommended.

**Q: Can one Jenkins validate repos for different clusters?**  
A: Yes! Validation doesn't need cluster access. For deployments, you'd need cluster credentials.

**Q: How do I add a new validation type?**  
A: Create a new Jenkinsfile with the validation steps, add it to the repo, update Jenkins job config.

**Q: What if Jenkins is down?**  
A: PRs won't get validated, but you can still merge manually (not recommended). Jenkins should be highly available.

**Q: Can Jenkins create ArgoCD applications instead of manual kubectl apply?**  
A: Yes, but there are better approaches:

1. **App of Apps Pattern (Best)**: Create a root ArgoCD app that watches `GrafanaLocal/argocd/applications/`. Commit new app manifests → ArgoCD auto-creates them. See `GrafanaLocal/argocd/applications/app-of-apps.yaml`.

2. **Jenkins Applies Directly**: Jenkins can run `kubectl apply -f <app-manifest.yaml>`, but this breaks GitOps (apps exist outside Git).

3. **Hybrid**: Jenkins validates app manifest, commits to Git, ArgoCD applies it. Best of both worlds.

**Recommendation**: Use App of Apps. Apply `app-of-apps.yaml` once, then all future apps are managed via Git commits.

---

## 📚 Additional Resources

- [Jenkins Pipeline Documentation](https://www.jenkins.io/doc/book/pipeline/)
- [Kubernetes Plugin for Jenkins](https://plugins.jenkins.io/kubernetes/)
- [GitOps Best Practices](https://www.gitops.tech/)
- [Terraform CI/CD Patterns](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
