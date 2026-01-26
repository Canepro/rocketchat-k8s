# Multi-Repository Setup Guide

This guide explains how to set up automated version checking and security validation for multiple GitHub repositories.

## Overview

The setup scripts now support multiple repositories. You can configure automated jobs for:
- `rocketchat-k8s` (default)
- `central-observability-hub-stack` (or any other repository)

**Important**: The repository name must match the **GitHub repository name**, not your local directory name.

## Quick Setup for Multiple Repositories

### Option 1: Use the Helper Script (Recommended)

```bash
# Set Jenkins URL (optional)
export JENKINS_URL="https://jenkins.canepro.me"

# Or use port-forward
kubectl -n jenkins port-forward pod/jenkins-0 8080:8080
export JENKINS_URL="http://127.0.0.1:8080"

# Set up jobs for all configured repositories
bash .jenkins/setup-all-repos.sh
```

This will create jobs for all repositories listed in `setup-all-repos.sh`.

### Option 2: Set Up Individual Repositories

```bash
# For rocketchat-k8s (default)
bash .jenkins/create-version-check-job.sh
bash .jenkins/create-security-validation-job.sh

# For central-observability-hub-stack (GitHub repo name, not local dir name)
bash .jenkins/create-version-check-job.sh Canepro central-observability-hub-stack version-check-central-observability-hub-stack
bash .jenkins/create-security-validation-job.sh Canepro central-observability-hub-stack security-validation-central-observability-hub-stack
```

## Script Usage

Both scripts now accept optional parameters:

```bash
bash .jenkins/create-version-check-job.sh [repo-owner] [repo-name] [job-name]
bash .jenkins/create-security-validation-job.sh [repo-owner] [repo-name] [job-name]
```

**Parameters:**
- `repo-owner`: GitHub repository owner (default: `Canepro`)
- `repo-name`: Repository name (default: `rocketchat-k8s`)
- `job-name`: Jenkins job name (default: `version-check-{repo-name}` or `security-validation-{repo-name}`)

**Examples:**

```bash
# Default (rocketchat-k8s)
bash .jenkins/create-version-check-job.sh

# Central Observability Hub Stack repository
bash .jenkins/create-version-check-job.sh Canepro central-observability-hub-stack version-check-central-observability-hub-stack

# Custom repository
bash .jenkins/create-version-check-job.sh myorg myrepo version-check-myrepo
```

## Job Naming Convention

Jobs are automatically named to avoid conflicts:
- `version-check-{repo-name}` - Version checking job
- `security-validation-{repo-name}` - Security validation job

Examples:
- `version-check-rocketchat-k8s`
- `version-check-central-observability-hub-stack`
- `security-validation-rocketchat-k8s`
- `security-validation-central-observability-hub-stack`

## Customizing Repository List

Edit `.jenkins/setup-all-repos.sh` to add or remove repositories:

```bash
# Add your repositories here
# Format: "owner:github-repo-name:description"
# NOTE: Use GitHub repository name, NOT local directory name
REPOS=(
  "Canepro:rocketchat-k8s:RocketChat K8s Infrastructure"
  "Canepro:central-observability-hub-stack:Central Observability Hub Stack"
  "Canepro:my-other-repo:My Other Repository"
)
```

Format: `"owner:repo-name:description"`

## Requirements

All repositories need:
1. **Jenkinsfile** in `.jenkins/` directory:
   - `.jenkins/version-check.Jenkinsfile`
   - `.jenkins/security-validation.Jenkinsfile`

2. **GitHub token** with access to the repository (configured in Jenkins as `github-token`)

3. **Same structure** (or compatible) as `rocketchat-k8s`:
   - `VERSIONS.md` (for version checking)
   - `terraform/` or infrastructure code (for security validation)
   - `values.yaml` or similar (for version checking)

## Verifying Setup

Check if jobs were created:

```bash
# Check specific job
JOB_NAME="version-check-central-observability-hub-stack" bash .jenkins/check-job.sh
JOB_NAME="security-validation-central-observability-hub-stack" bash .jenkins/check-job.sh

# Or list all jobs
curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/api/json?tree=jobs[name]" | jq -r '.jobs[].name'
```

## Manual Trigger

Trigger jobs manually for testing:

```bash
# Version check for central-observability-hub-stack
curl -X POST -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/version-check-central-observability-hub-stack/build"

# Security validation for central-observability-hub-stack
curl -X POST -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/security-validation-central-observability-hub-stack/build"
```

## Schedule

All jobs use the same schedule (configurable per job):
- **Version check**: Weekdays at 5 PM (`H 17 * * 1-5`)
- **Security validation**: Weekdays at 6 PM (`H 18 * * 1-5`)

To change schedules, update the job configuration in Jenkins UI or edit the XML config files.

## Troubleshooting

### Job Fails for New Repository

1. **Check Jenkinsfile exists**: The repository must have `.jenkins/version-check.Jenkinsfile` and `.jenkins/security-validation.Jenkinsfile`
2. **Check GitHub access**: The `github-token` credential must have access to the repository
3. **Check repository structure**: The pipeline expects certain files (VERSIONS.md, terraform/, etc.)

### Different Repository Structure

If your repository has a different structure, you may need to:
1. Copy and customize the Jenkinsfiles for that repository
2. Update the pipeline to match your repository structure
3. Or create repository-specific Jenkinsfiles

## Related Documentation

- `.jenkins/SETUP_AUTOMATED_JOBS.md` - General setup guide
- `.jenkins/VERSION_CHECKING.md` - Version checking details
- `.jenkins/SECURITY_VALIDATION.md` - Security validation details
