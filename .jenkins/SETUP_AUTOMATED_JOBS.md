# Setting Up Automated Jenkins Jobs

This guide explains how to set up the automated version checking and security validation Jenkins jobs.

## Overview

Two automated jobs are available:

1. **version-check** - Checks for component version updates and creates PRs/issues
2. **security-validation** - Scans infrastructure code for security issues and creates PRs/issues

Both jobs run on a weekday schedule and are regular Pipeline jobs (not multibranch).

## Prerequisites

- Jenkins is deployed and accessible
- GitHub token credential (`github-token`) is available in Jenkins (prefer GitOps-provisioned via ESO + Kubernetes Credentials Provider)
- Kubernetes access to retrieve Jenkins admin credentials (optional, can provide manually)
- `kubectl` configured (if using Kubernetes secret for credentials)

## Quick Setup (Recommended)

This repo includes scripts that handle CSRF crumbs + session cookies (Jenkins often requires both).

### Option 1: Using Setup Scripts (Recommended)

```bash
# Set Jenkins URL (if not using default)
export JENKINS_URL="https://jenkins.canepro.me"

# Or use port-forward for local access
kubectl -n jenkins port-forward pod/jenkins-0 8080:8080
export JENKINS_URL="http://127.0.0.1:8080"

# Create version-check job
bash .jenkins/create-version-check-job.sh

# Create security-validation job
bash .jenkins/create-security-validation-job.sh
```

### Option 1b: Multi-Repository Setup (Recommended when you run multiple repos)

Use the helper to create both jobs for a configured list of repos:

```bash
# Edit this file to add/remove repos:
# .jenkins/setup-all-repos.sh
bash .jenkins/setup-all-repos.sh
```

### Option 1c: One-off Setup for a Specific Repository

Important: Use the **GitHub repository name**, not your local directory name.

```bash
# Example: central-observability-hub-stack
bash .jenkins/create-version-check-job.sh Canepro central-observability-hub-stack version-check-central-observability-hub-stack
bash .jenkins/create-security-validation-job.sh Canepro central-observability-hub-stack security-validation-central-observability-hub-stack
```

### Option 2: Manual Setup via Jenkins UI

1. **Create New Pipeline Job**
   - Go to Jenkins → New Item
   - Enter job name: `version-check` (or `security-validation`)
   - Select **Pipeline** (not Multibranch Pipeline)
   - Click OK

2. **Configure Pipeline**
   - **Definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `https://github.com/Canepro/rocketchat-k8s`
   - **Credentials**: Select `github-token`
   - **Branches to build**: `*/master`
   - **Script Path**: 
     - For version-check: `.jenkins/version-check.Jenkinsfile`
     - For security-validation: `.jenkins/security-validation.Jenkinsfile`

3. **Configure Schedule**
   - Scroll to **Build Triggers**
   - Check **Build periodically**
  - **Schedule**:
    - Version-check: `H 17 * * 1-5` (weekdays at 5 PM, after cluster starts at 4 PM)
    - Security-validation: `H 18 * * 1-5` (weekdays at 6 PM, after cluster starts at 4 PM)

4. **Save** the job

### Option 3: Using Jenkins CLI/REST API

```bash
# Get Jenkins credentials
JENKINS_USER=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.username}' | base64 -d)
JENKINS_PASSWORD=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d)
JENKINS_URL="https://jenkins.canepro.me"

# Get CSRF token
CRUMB=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/crumbIssuer/api/json" | jq -r '.crumb')
CRUMB_FIELD=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/crumbIssuer/api/json" | jq -r '.crumbRequestField')

# Create version-check job
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "$CRUMB_FIELD:$CRUMB" \
  -H "Content-Type: application/xml" \
  --data-binary @.jenkins/version-check-job-config.xml \
  "$JENKINS_URL/createItem?name=version-check"

# Create security-validation job
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "$CRUMB_FIELD:$CRUMB" \
  -H "Content-Type: application/xml" \
  --data-binary @.jenkins/security-validation-job-config.xml \
  "$JENKINS_URL/createItem?name=security-validation"
```

## Verify Jobs Are Created

```bash
# Check if jobs exist
bash .jenkins/scripts/check-job.sh

# Or check specific job
JOB_NAME="version-check" bash .jenkins/scripts/check-job.sh
JOB_NAME="security-validation" bash .jenkins/scripts/check-job.sh
```

## Troubleshooting: "Failed to get CSRF token"

The create-job scripts read Jenkins admin credentials from the Kubernetes secret `jenkins-admin` in namespace `jenkins`. If you see **Failed to get CSRF token (HTTP 401)** or **(HTTP 000)**:

1. **HTTP 401 (Unauthorized)**  
   Jenkins often requires an **API token** for scripted auth, not the login password.  
   - In Jenkins: **Manage Jenkins** → **Users** → your user → **Configure** → **Add new Token** (API Token).  
   - Then run:  
     `export JENKINS_PASSWORD="your-api-token"`  
     `bash .jenkins/create-version-check-job.sh`  
   - Or ensure the secret `jenkins-admin` contains the API token in the `password` field (not the web login password).

2. **HTTP 000 or connection errors**  
   - Check that `JENKINS_URL` is reachable from your machine (VPN, DNS, firewall).  
   - If Jenkins is only reachable via port-forward:  
     `kubectl -n jenkins port-forward pod/jenkins-0 8080:8080`  
     `export JENKINS_URL="http://127.0.0.1:8080"`  
     then run the create-job script.

3. **kubectl / secret**  
   - Ensure your kube context can access the `jenkins` namespace:  
     `kubectl get secret jenkins-admin -n jenkins`  
   - If the secret is missing or wrong, set credentials manually:  
     `export JENKINS_USER="your-username"`  
     `export JENKINS_PASSWORD="your-api-token"`  
     then run the script.

## Manual Trigger

You can trigger jobs manually:

```bash
# Recommended (handles CSRF + session cookies)
bash .jenkins/test-job-trigger.sh version-check-rocketchat-k8s
bash .jenkins/test-job-trigger.sh security-validation-rocketchat-k8s
```

## Schedule Configuration

Both jobs use cron syntax for scheduling:

- **version-check**: `H 17 * * 1-5` - Weekdays (Mon-Fri) at 5 PM (randomized minute, 17:00-17:59)
- **security-validation**: `H 18 * * 1-5` - Weekdays (Mon-Fri) at 6 PM (randomized minute, 18:00-18:59)

**Note**: These schedules are set to run after the cluster auto-starts at 4 PM and before it shuts down at 11 PM on weekdays.

The `H` symbol randomizes the minute to avoid all jobs running at exactly the same time.

To change the schedule, edit the job configuration XML files:
- `.jenkins/version-check-job-config.xml` - Line with `<spec>H 17 * * 1-5</spec>`
- `.jenkins/security-validation-job-config.xml` - Line with `<spec>H 18 * * 1-5</spec>`

Or update via Jenkins UI: Job → Configure → Build Triggers → Build periodically

## What These Jobs Do

### version-check Job

1. Checks latest versions of:
   - Terraform providers (Azure Provider)
   - Container images (RocketChat, NATS, observability stack)
   - Helm charts (RocketChat, Traefik, MongoDB Operator)

2. Compares with current versions in:
   - `VERSIONS.md`
   - `values.yaml`
   - `terraform/main.tf`
   - `ops/manifests/*.yaml`

3. Creates PRs/issues based on risk:
   - **Critical** (major version): Creates/updates a single open GitHub Issue (de-duped via comments)
   - **High/Medium** (minor/patch): Creates/updates a single open GitHub PR (de-duped via reusing the branch + comments)
   - **Note**: The job can create/update both in one run (breaking issue + non-breaking PR)

4. Automatically updates:
   - `VERSIONS.md` with new versions
   - Code files with new version numbers

### security-validation Job

1. Runs security scanners:
   - **tfsec** - Terraform security scanner
   - **checkov** - Infrastructure as Code security scanner
   - **trivy** - Container image vulnerability scanner

2. Assesses risk levels:
   - Critical, High, Medium, Low

3. Creates PRs/issues based on findings:
   - **Critical/High**: Creates GitHub Issue
   - **Medium/Low** (aggregated): Creates PR with fixes

## Troubleshooting

### Job Fails to Create

- Check Jenkins credentials are correct
- Verify CSRF protection is working
- Check Jenkins logs: `kubectl logs -n jenkins jenkins-0 -c jenkins --tail=50`

### Job Runs But Fails

- Check job console output in Jenkins UI
- Verify GitHub token has proper permissions (repo, issues, pull requests)
- Check Kubernetes agent labels match pipeline requirements:
  - version-check needs: `version-checker` agent
  - security-validation needs: `security` agent

### GitHub API Errors

- Verify `github-token` credential is valid
- Check token has permissions: `repo`, `workflow` (and optionally `admin:repo_hook` if you want Jenkins managing webhooks)
- Token should have access to `Canepro/rocketchat-k8s` repository

### Agent Not Found

If you see "agent not found" errors, you need to configure Kubernetes agents in Jenkins:

1. Go to Jenkins → Manage Jenkins → Manage Nodes and Clouds
2. Configure Kubernetes Cloud
3. Add pod templates with labels:
   - `version-checker` - for version-check job
   - `security` - for security-validation job

Or update the Jenkinsfiles to use existing agent labels (like `default`).

## Next Steps

After setting up the jobs:

1. **Test manually**: Trigger jobs manually to verify they work
2. **Monitor first runs**: Check job outputs and PRs/issues created
3. **Adjust thresholds**: Edit pipeline files to adjust risk thresholds
4. **Review PRs**: The jobs will create PRs automatically - review and merge as needed

## Multi-Repository Support

The setup scripts support multiple repositories. Use either:
- `.jenkins/setup-all-repos.sh` (best for repeatable setup)
- `create-*-job.sh` with arguments (best for one-off jobs)

All jobs should be named to avoid collisions:
- `version-check-{repo-name}`
- `security-validation-{repo-name}`

## Related Documentation

- `.jenkins/VERSION_CHECKING.md` - Version checking details
- `.jenkins/SECURITY_VALIDATION.md` - Security validation details
- `.jenkins/README.md` - General Jenkins setup
- `.jenkins/GITHUB_CREDENTIALS_SETUP.md` - How `github-token` is provisioned (GitOps-first)
