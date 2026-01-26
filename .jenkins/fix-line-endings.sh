#!/bin/bash
# Quick fix for Windows line endings in bash scripts
# Run this in WSL/bash to convert CRLF to LF

if [ -f .jenkins/create-job.sh ]; then
  dos2unix .jenkins/create-job.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/create-job.sh || \
  tr -d '\r' < .jenkins/create-job.sh > .jenkins/create-job.sh.tmp && mv .jenkins/create-job.sh.tmp .jenkins/create-job.sh
  echo "✅ Fixed line endings in create-job.sh"
fi

if [ -f .jenkins/test-auth.sh ]; then
  dos2unix .jenkins/test-auth.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/test-auth.sh || \
  tr -d '\r' < .jenkins/test-auth.sh > .jenkins/test-auth.sh.tmp && mv .jenkins/test-auth.sh.tmp .jenkins/test-auth.sh
  echo "✅ Fixed line endings in test-auth.sh"
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

if [ -f .jenkins/check-versions.sh ]; then
  dos2unix .jenkins/check-versions.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/check-versions.sh || \
  tr -d '\r' < .jenkins/check-versions.sh > .jenkins/check-versions.sh.tmp && mv .jenkins/check-versions.sh.tmp .jenkins/check-versions.sh
  echo "✅ Fixed line endings in check-versions.sh"
fi

if [ -f .jenkins/create-security-pr.sh ]; then
  dos2unix .jenkins/create-security-pr.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/create-security-pr.sh || \
  tr -d '\r' < .jenkins/create-security-pr.sh > .jenkins/create-security-pr.sh.tmp && mv .jenkins/create-security-pr.sh.tmp .jenkins/create-security-pr.sh
  echo "✅ Fixed line endings in create-security-pr.sh"
fi

if [ -f .jenkins/update-versions-md.sh ]; then
  dos2unix .jenkins/update-versions-md.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/update-versions-md.sh || \
  tr -d '\r' < .jenkins/update-versions-md.sh > .jenkins/update-versions-md.sh.tmp && mv .jenkins/update-versions-md.sh.tmp .jenkins/update-versions-md.sh
  echo "✅ Fixed line endings in update-versions-md.sh"
fi

if [ -f .jenkins/delete-old-jobs.sh ]; then
  dos2unix .jenkins/delete-old-jobs.sh 2>/dev/null || \
  sed -i 's/\r$//' .jenkins/delete-old-jobs.sh || \
  tr -d '\r' < .jenkins/delete-old-jobs.sh > .jenkins/delete-old-jobs.sh.tmp && mv .jenkins/delete-old-jobs.sh.tmp .jenkins/delete-old-jobs.sh
  echo "✅ Fixed line endings in delete-old-jobs.sh"
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
