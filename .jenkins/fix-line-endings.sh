#!/bin/bash
# Quick fix for Windows line endings in bash scripts
# Run this in WSL/bash to convert CRLF to LF

if [ -f .jenkins/scripts/create-job.sh ]; then
  dos2unix .jenkins/scripts/create-job.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/scripts/create-job.sh || \
  tr -d '\r' < .jenkins/scripts/create-job.sh > .jenkins/scripts/create-job.sh.tmp && mv .jenkins/scripts/create-job.sh.tmp .jenkins/scripts/create-job.sh
  echo "✅ Fixed line endings in scripts/create-job.sh"
fi

if [ -f .jenkins/scripts/test-auth.sh ]; then
  dos2unix .jenkins/scripts/test-auth.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/scripts/test-auth.sh || \
  tr -d '\r' < .jenkins/scripts/test-auth.sh > .jenkins/scripts/test-auth.sh.tmp && mv .jenkins/scripts/test-auth.sh.tmp .jenkins/scripts/test-auth.sh
  echo "✅ Fixed line endings in scripts/test-auth.sh"
fi

if [ -f .jenkins/create-version-check-job.sh ]; then
  dos2unix .jenkins/create-version-check-job.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/create-version-check-job.sh || \
  tr -d '\r' < .jenkins/create-version-check-job.sh > .jenkins/create-version-check-job.sh.tmp && mv .jenkins/create-version-check-job.sh.tmp .jenkins/create-version-check-job.sh
  echo "✅ Fixed line endings in create-version-check-job.sh"
fi

if [ -f .jenkins/create-security-validation-job.sh ]; then
  dos2unix .jenkins/create-security-validation-job.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/create-security-validation-job.sh || \
  tr -d '\r' < .jenkins/create-security-validation-job.sh > .jenkins/create-security-validation-job.sh.tmp && mv .jenkins/create-security-validation-job.sh.tmp .jenkins/create-security-validation-job.sh
  echo "✅ Fixed line endings in create-security-validation-job.sh"
fi

if [ -f .jenkins/setup-all-repos.sh ]; then
  dos2unix .jenkins/setup-all-repos.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/setup-all-repos.sh || \
  tr -d '\r' < .jenkins/setup-all-repos.sh > .jenkins/setup-all-repos.sh.tmp && mv .jenkins/setup-all-repos.sh.tmp .jenkins/setup-all-repos.sh
  echo "✅ Fixed line endings in setup-all-repos.sh"
fi

if [ -f .jenkins/scripts/delete-old-jobs.sh ]; then
  dos2unix .jenkins/scripts/delete-old-jobs.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/scripts/delete-old-jobs.sh || \
  tr -d '\r' < .jenkins/scripts/delete-old-jobs.sh > .jenkins/scripts/delete-old-jobs.sh.tmp && mv .jenkins/scripts/delete-old-jobs.sh.tmp .jenkins/scripts/delete-old-jobs.sh
  echo "✅ Fixed line endings in scripts/delete-old-jobs.sh"
fi

if [ -f .jenkins/test-job-trigger.sh ]; then
  dos2unix .jenkins/test-job-trigger.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/test-job-trigger.sh || \
  tr -d '\r' < .jenkins/test-job-trigger.sh > .jenkins/test-job-trigger.sh.tmp && mv .jenkins/test-job-trigger.sh.tmp .jenkins/test-job-trigger.sh
  echo "✅ Fixed line endings in test-job-trigger.sh"
fi

# Fix Jenkinsfile line endings
if [ -f .jenkins/version-check.Jenkinsfile ]; then
  dos2unix .jenkins/version-check.Jenkinsfile 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/version-check.Jenkinsfile || \
  tr -d '\r' < .jenkins/version-check.Jenkinsfile > .jenkins/version-check.Jenkinsfile.tmp && mv .jenkins/version-check.Jenkinsfile.tmp .jenkins/version-check.Jenkinsfile
  echo "✅ Fixed line endings in version-check.Jenkinsfile"
fi

if [ -f .jenkins/security-validation.Jenkinsfile ]; then
  dos2unix .jenkins/security-validation.Jenkinsfile 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/security-validation.Jenkinsfile || \
  tr -d '\r' < .jenkins/security-validation.Jenkinsfile > .jenkins/security-validation.Jenkinsfile.tmp && mv .jenkins/security-validation.Jenkinsfile.tmp .jenkins/security-validation.Jenkinsfile
  echo "✅ Fixed line endings in security-validation.Jenkinsfile"
fi

if [ -f .jenkins/terraform-validation-with-security.Jenkinsfile ]; then
  dos2unix .jenkins/terraform-validation-with-security.Jenkinsfile 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/terraform-validation-with-security.Jenkinsfile || \
  tr -d '\r' < .jenkins/terraform-validation-with-security.Jenkinsfile > .jenkins/terraform-validation-with-security.Jenkinsfile.tmp && mv .jenkins/terraform-validation-with-security.Jenkinsfile.tmp .jenkins/terraform-validation-with-security.Jenkinsfile
  echo "✅ Fixed line endings in terraform-validation-with-security.Jenkinsfile"
fi

if [ -f .jenkins/scripts/check-job.sh ]; then
  dos2unix .jenkins/scripts/check-job.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/scripts/check-job.sh || \
  tr -d '\r' < .jenkins/scripts/check-job.sh > .jenkins/scripts/check-job.sh.tmp && mv .jenkins/scripts/check-job.sh.tmp .jenkins/scripts/check-job.sh
  echo "✅ Fixed line endings in scripts/check-job.sh"
fi

if [ -f .jenkins/scripts/sync-jenkinsfiles-to-repo.sh ]; then
  dos2unix .jenkins/scripts/sync-jenkinsfiles-to-repo.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/scripts/sync-jenkinsfiles-to-repo.sh || \
  tr -d '\r' < .jenkins/scripts/sync-jenkinsfiles-to-repo.sh > .jenkins/scripts/sync-jenkinsfiles-to-repo.sh.tmp && mv .jenkins/scripts/sync-jenkinsfiles-to-repo.sh.tmp .jenkins/scripts/sync-jenkinsfiles-to-repo.sh
  echo "✅ Fixed line endings in scripts/sync-jenkinsfiles-to-repo.sh"
fi

if [ -f .jenkins/scripts/setup-other-repos.sh ]; then
  dos2unix .jenkins/scripts/setup-other-repos.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/scripts/setup-other-repos.sh || \
  tr -d '\r' < .jenkins/scripts/setup-other-repos.sh > .jenkins/scripts/setup-other-repos.sh.tmp && mv .jenkins/scripts/setup-other-repos.sh.tmp .jenkins/scripts/setup-other-repos.sh
  echo "✅ Fixed line endings in scripts/setup-other-repos.sh"
fi
