# Jenkins CI Validation Pipelines

This directory contains Jenkinsfiles for CI validation of the `rocketchat-k8s` repository.

## Available Pipelines

### `terraform-validation.Jenkinsfile`
Validates Terraform infrastructure code using **Azure Workload Identity** for authentication:
- Format check (`terraform fmt -check`)
- Syntax validation (`terraform validate`)
- Plan generation (`terraform plan`) with Azure state backend

**Agent**: `terraform-azure` (Azure CLI image with Terraform installed)
**Authentication**: Uses Azure Workload Identity (federated credentials via `jenkins` service account)

**Note**: The pipeline uses `terraform.tfvars.example` for CI validation (placeholder values). Real secrets are never stored in blob storage or git.

### `helm-validation.Jenkinsfile`
Validates Helm charts and Kubernetes manifests:
- Helm template rendering
- Kubeconform validation
- YAML linting

**Agent**: `helm` (Alpine Helm image with kubectl and kubeconform)

### `version-check.Jenkinsfile`
Automated version checking pipeline:
- Checks for latest versions of all components
- Compares with current versions in code
- Creates/updates GitHub Issues and PRs for updates based on risk assessment (de-duped)
- Automatically updates `VERSIONS.md` and code files

**Agent**: `version-checker` (Alpine with version checking tools)
**Schedule**: Weekdays at 5 PM (`H 17 * * 1-5`, after cluster auto-start at 16:00)

**GitHub output (summary)**:
- **Breaking updates**: one open issue (updated via comments)
- **Non-breaking updates**: one open PR (updated by pushing to the same branch + commenting)
- **Job failures**: GitHub issue notification (so you don't need to log into Jenkins daily)

**Implementation**: Uses secure Git push (`GIT_ASKPASS`, no token in config), workspace-scoped git commands, and validated Terraform version extraction. See [VERSION_CHECKING.md](VERSION_CHECKING.md#pipeline-implementation-notes).

### `security-validation.Jenkinsfile`
Automated security validation pipeline:
- Scans Terraform code (tfsec, checkov)
- Scans container images (trivy)
- Assesses risk levels
- Creates/updates PRs/issues for remediation (de-duped) and notifies on job failures

**Agent**: `security` (Alpine with security scanning tools)
**Schedule**: Weekdays at 6 PM (`H 18 * * 1-5`, after cluster auto-start at 16:00)

## Usage

### CI Validation Pipelines (Multibranch)

These Jenkinsfiles are used by Jenkins Multibranch Pipeline jobs that automatically:
- Discover branches and pull requests
- Run validation on PRs
- Report status back to GitHub

### Automated Jobs (Scheduled)

The version-check and security-validation pipelines run as scheduled jobs:
- Run on a weekday schedule (see above) on `master`
- Create PRs/issues automatically
- Update code and documentation

**Setup**: See `.jenkins/SETUP_AUTOMATED_JOBS.md` (single source of truth).

### Split-agent hybrid (Controller on OKE, Agent on AKS)

When the Jenkins controller runs on OKE and a static agent runs on AKS, see [JENKINS-SPLIT-AGENT-PLAN-aks.md](JENKINS-SPLIT-AGENT-PLAN-aks.md) for the AKS-side plan, manifest locations, and cutover steps. Canonical plan and runbook are in the hub-docs repo.

## Setup in Jenkins

1. **Create the `github-token` credential first** (Manage Jenkins → Credentials). Use the same credential ID so job config and Jenkinsfiles keep working. On OKE you can add it in the UI or feed it from a K8s secret; see [GITHUB_CREDENTIALS_SETUP.md](GITHUB_CREDENTIALS_SETUP.md) if needed.
2. Create a **Multibranch Pipeline** job named `rocketchat-k8s`
3. **Branch Sources** section:
   - Click **"Add source"** button (at the top of Branch Sources section)
   - Select **"GitHub"** from the dropdown
4. Configure the GitHub branch source:
   - **Repository HTTPS URL**: `https://github.com/Canepro/rocketchat-k8s`
   - **Credentials**: Select **`github-token`** from dropdown (required for PR status reporting)
   - **Behaviours** (click "Add" to configure):
     - **Discover branches**: Strategy = "Exclude branches that are also filed as PRs"
     - **Discover pull requests from origin**: Strategy = "The current pull request revision"
     - **Trust**: "From users with Admin or Write permission"
5. **Build Configuration**:
   - **Mode**: "by Jenkinsfile"
   - **Script Path**: `.jenkins/terraform-validation.Jenkinsfile` (or `.jenkins/helm-validation.Jenkinsfile`)
     - This is the path relative to the repository root
6. **Save** → **Scan Multibranch Pipeline Now**

**UI:** Go to Jenkins UI (e.g. OKE: `https://jenkins-oke.canepro.me` or production: `https://jenkins.canepro.me`) and use credential ID **`github-token`** for the GitHub branch source.

### CLI setup (when UI is painful)
Use the repo script which handles CSRF + session cookies. Create `github-token` on the target Jenkins first.

```bash
# OKE (before domain cutover):
export JENKINS_URL="https://jenkins-oke.canepro.me"
export JOB_NAME="rocketchat-k8s"
export CONFIG_FILE=".jenkins/job-config.xml"
bash .jenkins/scripts/create-job.sh

# Production (after cutover):
export JENKINS_URL="https://jenkins.canepro.me"
# ... same JOB_NAME and CONFIG_FILE ...

# Debugging via port-forward (AKS or local):
kubectl -n jenkins port-forward pod/jenkins-0 8080:8080
export JENKINS_URL="http://127.0.0.1:8080"
bash .jenkins/scripts/create-job.sh
```

**Migrating from AKS Jenkins:** See [JENKINS-SPLIT-AGENT-PLAN-aks.md](JENKINS-SPLIT-AGENT-PLAN-aks.md) (Jobs, pipelines, multibranch, and credentials) and hub-docs plan §8.1 for recreate/export/import options and credential checklist.

## GitHub Webhook

Configure webhook in repository settings:

| When        | Webhook URL |
|-------------|-------------|
| OKE (before cutover) | `https://jenkins-oke.canepro.me/github-webhook/` |
| After cutover       | `https://jenkins.canepro.me/github-webhook/`     |

- **Events**: Pull requests, Pushes  
- **Content type**: `application/json`

## Jenkins UI login

Jenkins admin credentials are stored in Azure Key Vault and synced into Kubernetes via External Secrets Operator.
To retrieve the current credentials:

```bash
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d; echo
```

## GitHub token credential (how it is provided)

This repo provisions the `github-token` Jenkins credential via GitOps:
- **Source of truth**: Azure Key Vault secret `jenkins-github-token`
- **Sync**: `ops/secrets/externalsecret-jenkins.yaml` (ESO → `jenkins/secret/jenkins-github`)
- **Discovery**: Jenkins Kubernetes Credentials Provider auto-discovers it as a **username/password** credential with ID `github-token`

If `github-token` is missing in Jenkins dropdowns, see `.jenkins/GITHUB_CREDENTIALS_SETUP.md`.
