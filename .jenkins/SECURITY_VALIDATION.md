# Security Validation Pipeline

This document describes the automated security validation workflow that scans infrastructure code and creates PRs/issues based on risk assessment.

## Overview

The security validation pipeline:
1. **Scans** Terraform code, Kubernetes manifests, and container images
2. **Assesses** risk levels based on findings
3. **Creates** GitHub PRs for high-priority fixes or Issues for critical vulnerabilities

## Tools Used

- **tfsec**: Terraform security scanner
- **checkov**: Infrastructure as Code security scanner  
- **trivy**: Container image vulnerability scanner
- **kube-score**: Kubernetes manifest security scanner

## Risk Assessment

Findings are categorized by severity:
- **CRITICAL**: Immediate action required → Creates GitHub Issue
- **HIGH**: High priority → Creates automated PR with fixes
- **MEDIUM**: Medium priority → Logged, optional PR
- **LOW**: Low priority → Logged only

## Thresholds

Default thresholds (configurable via environment variables):
- `CRITICAL_THRESHOLD=10` - Number of critical findings to trigger issue
- `HIGH_THRESHOLD=20` - Number of high findings to trigger PR
- `MEDIUM_THRESHOLD=50` - Number of medium findings to create issue

## Setup

### Recommended: Standalone Scheduled Job

Create a separate Jenkins job that runs on schedule (daily):

**Quick Setup:**
```bash
bash .jenkins/create-security-validation-job.sh
```

**Manual Setup:**
1. **Create Pipeline job** (not multibranch) named `security-validation`
2. **Use**: `.jenkins/security-validation.Jenkinsfile`
3. **Schedule**: `H 3 * * *` (daily at 3 AM)
4. **SCM**: Git repository `https://github.com/Canepro/rocketchat-k8s`, branch `master`
5. **Credentials**: Use `github-token` for GitHub API access

See `.jenkins/SETUP_AUTOMATED_JOBS.md` for detailed setup instructions.

### Alternative: Integrate into Existing Pipeline

Add security stages to `.jenkins/terraform-validation.Jenkinsfile`:

```groovy
// Add after Terraform Validate stage
stage('Security Scan') {
  steps {
    sh '''
      # Install tfsec
      curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
      
      # Run security scan
      cd terraform
      tfsec . --format json --out ../tfsec-results.json || true
      tfsec . || true
    '''
  }
}
```

## Usage

### Manual Run

Run security validation manually:

```bash
# Run security scan
bash .jenkins/create-security-pr.sh

# Or use the full pipeline
# (requires Jenkins with security-validation.Jenkinsfile configured)
```

### Automatic Run

The pipeline runs automatically on:
- **Pull Requests**: Validates changes before merge
- **Master branch**: Full security scan on each commit
- **Scheduled**: Can be configured to run daily/weekly

## Output

Security scan results are:
- **Archived** as build artifacts (JSON files)
- **Displayed** in Jenkins console
- **Reported** to GitHub via PR comments or Issues

## Creating PRs/Issues

The pipeline automatically:
1. **Assesses risk** from scan results
2. **Creates GitHub Issue** if critical findings exceed threshold
3. **Creates PR** if high findings exceed threshold (with automated fixes)
4. **Comments on PR** with scan summary

### Manual PR Creation

```bash
# Set GitHub token
export GITHUB_TOKEN="your-token"

# Run risk assessment and create PR/issue
bash .jenkins/create-security-pr.sh
```

## Customization

### Adjust Risk Thresholds

Edit `.jenkins/security-validation.Jenkinsfile`:

```groovy
environment {
  CRITICAL_THRESHOLD = '5'   // Lower threshold = more sensitive
  HIGH_THRESHOLD = '10'
  MEDIUM_THRESHOLD = '30'
}
```

### Add Custom Scanners

Add new stages to the pipeline:

```groovy
stage('Custom Security Scan') {
  steps {
    sh '''
      # Your custom scanner here
      custom-scanner --output results.json
    '''
  }
}
```

## Troubleshooting

### Scanners Not Found

Ensure tools are installed in the Jenkins agent:

```groovy
stage('Install Tools') {
  steps {
    sh '''
      # Install all required tools
      curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
      pip3 install checkov
      # etc...
    '''
  }
}
```

### GitHub API Errors

Verify GitHub token has correct permissions:
- `repo` scope (for PR/Issue creation)
- `issues:write` (for creating issues)
- `pull_requests:write` (for creating PRs)

### No PRs/Issues Created

Check:
1. Risk thresholds are configured correctly
2. GitHub token has proper permissions
3. `action_required` is `true` in risk assessment
4. Jenkins has write access to repository

## Best Practices

1. **Start Conservative**: Begin with higher thresholds, adjust based on results
2. **Review Auto-Fixes**: Always review automated PRs before merging
3. **Regular Scans**: Run security scans on schedule (daily/weekly)
4. **Track Trends**: Monitor security findings over time
5. **Update Tools**: Keep security scanners updated to latest versions

## Integration with Existing Workflow

The security validation complements the existing validation:
- **terraform-validation.Jenkinsfile**: Format + syntax validation
- **security-validation.Jenkinsfile**: Security + risk assessment
- **helm-validation.Jenkinsfile**: Helm chart validation

All three can run in parallel or sequentially depending on your needs.
