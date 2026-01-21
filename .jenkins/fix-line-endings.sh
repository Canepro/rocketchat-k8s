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
