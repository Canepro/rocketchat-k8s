# Jenkins CI Validation Pipelines

This directory contains Jenkinsfiles for CI validation of the `rocketchat-k8s` repository.

## Available Pipelines

### `terraform-validation.Jenkinsfile`
Validates Terraform infrastructure code using **Azure Workload Identity** for authentication:
- Format check (`terraform fmt -check`)
- Syntax validation (`terraform validate`)
- Plan generation (`terraform plan`) with Azure state backend

**Agent**: `aks-agent` (static AKS agent; uses Azure Workload Identity via `jenkins` service account)
**Authentication**: Uses Azure Workload Identity (federated credentials via `jenkins` service account)

**Note**: The pipeline uses `terraform.tfvars.example` for CI validation (placeholder values). Real secrets are never stored in blob storage or git.

### `helm-validation.Jenkinsfile`
Validates Helm charts and Kubernetes manifests:
- Helm template rendering
- Kubeconform validation
- YAML linting

**Agent**: `aks-agent` (static AKS agent; repo push / PR validation)

### `version-check.Jenkinsfile`
Automated version checking pipeline:
- Checks for latest versions of all components
- Compares with current versions in code
- Creates/updates GitHub Issues and PRs for updates based on risk assessment (de-duped)
- Automatically updates `VERSIONS.md` and code files

**Agent**: `aks-agent` (static AKS agent)
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
- **Issues only** (no PRs): one canonical issue title **"Security: automated scan findings"**; de-dupe by finding that open issue and adding a comment; create the issue only if it doesn’t exist. Bodies built with jq; API failures are not hidden (`if ! curl ...; then echo "⚠️ WARNING: ..."; fi`).

**Agent**: `aks-agent` (static AKS agent)
**Schedule**: Weekdays at 6 PM (`H 18 * * 1-5`, after cluster auto-start at 16:00)

## Usage

### CI Validation Pipelines (Multibranch)

The **repo job** (multibranch pipeline, e.g. `rocketchat-k8s`) uses a **single** Script Path: `.jenkins/terraform-validation.Jenkinsfile`. So every branch and PR runs **Terraform validation** only. Helm validation (`.jenkins/helm-validation.Jenkinsfile`) does **not** run automatically on the same branches/PRs unless you add a second multibranch job with Script Path `.jenkins/helm-validation.Jenkinsfile`, or a multi-pipeline setup. See [WORKFLOWS-AND-STAGES.md](WORKFLOWS-AND-STAGES.md).

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

**Version-check PR logic:** **HIGH→issue**, **MEDIUM≥1→PR**. Breaking (major) updates open/update a single issue; non-breaking (high/medium) open/update a single PR. Uses **mikefarah/yq** (not apk/kislyuk yq) with **checksum verification**; **WORKDIR** and absolute paths for manifest updates and `curl -d @...` payloads. Single **ensure_label.sh** created in Install Tools and sourced in PR/issue/post blocks (minimal inline fallback in post if script missing). Update loop uses process substitution and **UPDATE_FAILED** so failed yq exits the main shell. Helm installer pinned to a version tag. See [STATIC-AGENT-REPO-SUGGESTIONS.md](STATIC-AGENT-REPO-SUGGESTIONS.md) and [WORKFLOWS-AND-STAGES.md](WORKFLOWS-AND-STAGES.md).

**Security:** Issues only (no PRs). One canonical issue title (e.g. "Security: automated scan findings"); de-dupe by finding that open issue and adding a comment; create the issue only if it doesn’t exist. Bodies built with jq; API failures are not hidden. See [STATIC-AGENT-REPO-SUGGESTIONS.md](STATIC-AGENT-REPO-SUGGESTIONS.md) for details.

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

**UI:** Go to Jenkins at **https://jenkins.canepro.me** (production; controller on OKE) and use credential ID **`github-token`** for the GitHub branch source.

### CLI setup (when UI is painful)
Use the repo script which handles CSRF + session cookies. Create `github-token` on the target Jenkins first.

```bash
# Production (Jenkins on OKE; domain cutover complete):
export JENKINS_URL="https://jenkins.canepro.me"
export JOB_NAME="rocketchat-k8s"
export CONFIG_FILE=".jenkins/job-config.xml"
bash .jenkins/scripts/create-job.sh

# Debugging via port-forward (when Jenkins pod is reachable):
kubectl -n jenkins port-forward pod/jenkins-0 8080:8080
export JENKINS_URL="http://127.0.0.1:8080"
bash .jenkins/scripts/create-job.sh
```

**Migrating from AKS Jenkins:** See [JENKINS-SPLIT-AGENT-PLAN-aks.md](JENKINS-SPLIT-AGENT-PLAN-aks.md) (Jobs, pipelines, multibranch, and credentials) and hub-docs plan §8.1 for recreate/export/import options and credential checklist.

## GitHub Webhook

Configure webhook in repository settings:

| Environment | Webhook URL |
|-------------|-------------|
| Production  | `https://jenkins.canepro.me/github-webhook/`     |

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
