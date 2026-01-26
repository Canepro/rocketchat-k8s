# Testing Checklist for Automated Jenkins Jobs

This checklist helps verify the new automated jobs work correctly before merging to master.

## Current Status

- **Branch**: `test/jenkins-pr-validation`
- **Jobs Created**: 4 repository-specific jobs
- **Next Step**: Test jobs, then create PR to merge

## Pre-Merge Testing

### 1. Verify Jobs Exist

```bash
# Check all jobs exist
JOB_NAME="version-check-rocketchat-k8s" bash .jenkins/check-job.sh
JOB_NAME="security-validation-rocketchat-k8s" bash .jenkins/check-job.sh
JOB_NAME="version-check-central-observability-hub-stack" bash .jenkins/check-job.sh
JOB_NAME="security-validation-central-observability-hub-stack" bash .jenkins/check-job.sh
```

### 2. Test Job Configuration

For each job, verify:
- ✅ Job exists in Jenkins UI
- ✅ Points to correct GitHub repository
- ✅ Uses correct Jenkinsfile path (`.jenkins/version-check.Jenkinsfile` or `.jenkins/security-validation.Jenkinsfile`)
- ✅ Schedule is set correctly (weekdays at 5 PM or 6 PM)

### 3. Manual Test Run (Recommended)

Trigger one job manually to verify it works:

```bash
# Test version-check for rocketchat-k8s
curl -X POST -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/version-check-rocketchat-k8s/build"

# Monitor in Jenkins UI: http://127.0.0.1:8080/job/version-check-rocketchat-k8s
```

**What to check:**
- ✅ Job starts successfully
- ✅ Checks out correct repository
- ✅ Finds Jenkinsfile
- ⚠️ May fail if Jenkinsfiles don't exist in target repos (expected for central-observability-hub-stack)

### 4. Verify Repository-Specific Configuration

Check that jobs point to correct repositories:
- `version-check-rocketchat-k8s` → `https://github.com/Canepro/rocketchat-k8s`
- `version-check-central-observability-hub-stack` → `https://github.com/Canepro/central-observability-hub-stack`

## Known Limitations

### For `central-observability-hub-stack`:

The jobs will be created, but they may fail initially because:
- The repository may not have `.jenkins/version-check.Jenkinsfile` yet
- The repository may not have `.jenkins/security-validation.Jenkinsfile` yet

**This is OK** - you can:
1. Copy the Jenkinsfiles to that repository later
2. Or customize them for that repository's structure
3. The jobs are configured correctly, they just need the pipeline files

## Before Creating PR

### Files to Commit

Make sure these are committed:
- ✅ `.jenkins/create-version-check-job.sh` (updated for multi-repo)
- ✅ `.jenkins/create-security-validation-job.sh` (updated for multi-repo)
- ✅ `.jenkins/setup-all-repos.sh` (new)
- ✅ `.jenkins/delete-old-jobs.sh` (new)
- ✅ `.jenkins/version-check-job-config.xml`
- ✅ `.jenkins/security-validation-job-config.xml`
- ✅ `.jenkins/MULTI_REPO_SETUP.md` (new)
- ✅ `.jenkins/SETUP_AUTOMATED_JOBS.md` (updated)
- ✅ `.jenkins/QUICK_START_AUTOMATED_JOBS.md` (updated)
- ✅ `.jenkins/VERSION_CHECKING.md` (updated)
- ✅ `.jenkins/fix-line-endings.sh` (updated)

### PR Description Template

```markdown
## Automated Jenkins Jobs for Multi-Repository Support

### Changes
- Added multi-repository support to version-check and security-validation jobs
- Created repository-specific jobs for `rocketchat-k8s` and `central-observability-hub-stack`
- Updated schedules to run weekdays (5 PM and 6 PM) after cluster starts at 4 PM
- Added cleanup script to remove old generic jobs

### Jobs Created
- `version-check-rocketchat-k8s`
- `security-validation-rocketchat-k8s`
- `version-check-central-observability-hub-stack`
- `security-validation-central-observability-hub-stack`

### Testing
- [x] Jobs created successfully
- [x] Old redundant jobs deleted
- [ ] Manual test run completed (optional)
- [ ] Verified job configurations in Jenkins UI

### Notes
- Jobs for `central-observability-hub-stack` may need Jenkinsfiles copied to that repository
- All jobs scheduled for weekdays after cluster auto-start (4 PM)
```

## After Merging to Master

1. **Jenkins will use the updated scripts** from master branch
2. **Jobs are already created** - they'll continue working
3. **For central-observability-hub-stack**: Copy/customize Jenkinsfiles to that repo when ready

## Quick Test Command

```bash
# Quick test: Trigger one job and check it starts
export JENKINS_URL="http://127.0.0.1:8080"
curl -X POST -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/version-check-rocketchat-k8s/build" && \
echo "Check job status at: $JENKINS_URL/job/version-check-rocketchat-k8s"
```
