# Automated Version Checking

This document describes how Jenkins automatically checks for version updates and creates PRs/issues.

## Overview

The version checking system:
1. **Checks** latest versions of all components (Terraform, Helm charts, container images)
2. **Compares** with current versions in `VERSIONS.md` and code
3. **Assesses** risk (major = critical, minor = medium)
4. **Creates** GitHub Issues for major updates, PRs for minor updates

## What Gets Checked

### Infrastructure
- **Terraform Azure Provider**: Checks Terraform Registry
- **Terraform version**: Checks Terraform releases

### Application Stack
- **RocketChat**: Checks GitHub releases
- **Helm Charts**: RocketChat, Traefik, MongoDB Operator
- **Container Images**: All images in `ops/manifests/` and `values.yaml`

### Observability
- **Prometheus Agent**: GitHub releases
- **OTel Collector**: GitHub releases
- **Other observability tools**: As listed in VERSIONS.md

## Risk Assessment

- **CRITICAL** (Major version): Creates GitHub Issue
  - Example: RocketChat 7.x → 8.x
  - Example: Terraform Provider 3.x → 4.x
  
- **HIGH** (Minor version, security): Creates PR with fixes
  - Example: RocketChat 8.0.1 → 8.0.2
  - Example: Security patches
  
- **MEDIUM** (Patch version): Creates PR for review
  - Example: 8.0.1 → 8.0.2 (patch)
  - Example: Dependency updates

## Setup

### Recommended: Separate Scheduled Job

Create a Jenkins job that runs on schedule (daily):

**Quick Setup:**
```bash
bash .jenkins/create-version-check-job.sh
```

**Manual Setup:**
1. **Create Pipeline job** (not multibranch) named `version-check`
2. **Use**: `.jenkins/version-check.Jenkinsfile`
3. **Schedule**: `H 17 * * 1-5` (weekdays at 5 PM, after cluster starts at 4 PM)
4. **SCM**: Git repository `https://github.com/Canepro/rocketchat-k8s`, branch `master`
5. **Credentials**: Use `github-token` for GitHub API access

See `.jenkins/SETUP_AUTOMATED_JOBS.md` for detailed setup instructions.

### Alternative: Add to Existing Pipeline

Add version checking stage to `.jenkins/terraform-validation.Jenkinsfile`:

```groovy
stage('Version Check') {
  when {
    // Only run on master branch or scheduled
    anyOf {
      branch 'master'
      expression { env.BRANCH_NAME == 'master' }
    }
  }
  steps {
    sh 'bash .jenkins/check-versions.sh'
  }
}
```

## How It Works

1. **Extract Current Versions**
   - Reads from `VERSIONS.md`
   - Parses `values.yaml` for image tags
   - Checks `terraform/main.tf` for provider versions

2. **Fetch Latest Versions**
   - GitHub Releases API for applications
   - Terraform Registry API for providers
   - Docker Hub/Container Registry APIs for images

3. **Compare and Assess**
   - Determines if update is major/minor/patch
   - Categorizes by risk level

4. **Create PR/Issue**
   - **Critical**: GitHub Issue (requires manual review)
   - **High/Medium**: Automated PR with version updates

## Example Output

```json
{
  "timestamp": "2026-01-26T19:00:00Z",
  "updates": {
    "critical": [
      "NATS Server: 2.4 → 2.10 (MAJOR)"
    ],
    "high": [
      "RocketChat: 8.0.1 → 8.0.2",
      "Prometheus Agent: 3.8.1 → 3.9.0"
    ],
    "medium": [
      "Alpine: 3.19 → 3.20"
    ]
  }
}
```

## Customization

### Adjust Risk Thresholds

Edit `.jenkins/check-versions.sh`:

```bash
# Change when PR vs Issue is created
if [ ${#CRITICAL_UPDATES[@]} -gt 0 ]; then
  # Create issue
elif [ ${#HIGH_UPDATES[@]} -gt 0 ] || [ ${#MEDIUM_UPDATES[@]} -ge 3 ]; then
  # Create PR (change threshold from 3 to your preference)
fi
```

### Add More Components

Edit `.jenkins/check-versions.sh` to add checks for:
- MongoDB Operator versions
- Traefik versions
- Other Helm charts
- Base images (Alpine, etc.)

## Integration with Security Pipeline

Version checking complements security scanning:
- **Security Pipeline**: Finds vulnerabilities in current versions
- **Version Pipeline**: Finds newer versions that may fix vulnerabilities

Both can run together for comprehensive dependency management.
