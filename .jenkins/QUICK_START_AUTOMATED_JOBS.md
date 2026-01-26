# Quick Start: Automated Jenkins Jobs

## TL;DR

Run these commands to set up automated version checking and security validation:

```bash
# Set Jenkins URL (optional, defaults to https://jenkins.canepro.me)
export JENKINS_URL="https://jenkins.canepro.me"

# Or use port-forward for local access
kubectl -n jenkins port-forward pod/jenkins-0 8080:8080
export JENKINS_URL="http://127.0.0.1:8080"

# Option 1: Set up for default repository (rocketchat-k8s)
bash .jenkins/create-version-check-job.sh
bash .jenkins/create-security-validation-job.sh

# Option 2: Set up for multiple repositories at once
bash .jenkins/setup-all-repos.sh

# Option 3: Set up for a specific repository
# NOTE: Use GitHub repository name, not local directory name
bash .jenkins/create-version-check-job.sh Canepro central-observability-hub-stack version-check-central-observability-hub-stack
bash .jenkins/create-security-validation-job.sh Canepro central-observability-hub-stack security-validation-central-observability-hub-stack
```

## What Gets Created

### version-check Job
- **Schedule**: Weekdays at 5 PM (after cluster starts at 4 PM)
- **What it does**: Checks for version updates, creates PRs/issues, auto-updates `VERSIONS.md`
- **Config**: `.jenkins/version-check-job-config.xml`
- **Pipeline**: `.jenkins/version-check.Jenkinsfile`

### security-validation Job
- **Schedule**: Weekdays at 6 PM (after cluster starts at 4 PM)
- **What it does**: Scans for security issues, creates PRs/issues for remediation
- **Config**: `.jenkins/security-validation-job-config.xml`
- **Pipeline**: `.jenkins/security-validation.Jenkinsfile`

## Verify Setup

```bash
# Check if jobs exist
JOB_NAME="version-check" bash .jenkins/check-job.sh
JOB_NAME="security-validation" bash .jenkins/check-job.sh
```

## Manual Trigger

```bash
# Trigger version-check
curl -X POST -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/version-check/build"

# Trigger security-validation
curl -X POST -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/security-validation/build"
```

## Next Steps

1. **Test the jobs**: Trigger manually and check outputs
2. **Review first PRs**: Jobs will create PRs automatically
3. **Adjust schedules**: Edit job configs if needed
4. **Monitor**: Check Jenkins UI for job status

## Troubleshooting

See `.jenkins/SETUP_AUTOMATED_JOBS.md` for detailed troubleshooting.

## Documentation

- `.jenkins/SETUP_AUTOMATED_JOBS.md` - Complete setup guide
- `.jenkins/MULTI_REPO_SETUP.md` - Multi-repository setup guide
- `.jenkins/VERSION_CHECKING.md` - Version checking details
- `.jenkins/SECURITY_VALIDATION.md` - Security validation details
