#!/bin/bash
# Helper script to set up automated jobs for multiple repositories
# Usage: bash setup-all-repos.sh

set -euo pipefail

echo "🚀 Setting up automated Jenkins jobs for multiple repositories"
echo ""

# Default Jenkins URL
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"

# Check if using port-forward
if [ "$JENKINS_URL" = "http://127.0.0.1:8080" ]; then
  echo "Using local port-forward: $JENKINS_URL"
else
  echo "Using Jenkins URL: $JENKINS_URL"
fi
echo ""

# Repository configurations
# Format: "owner:repo-name:description"
# NOTE: repo-name must match the GitHub repository name (not local directory name)
REPOS=(
  "Canepro:rocketchat-k8s:RocketChat K8s Infrastructure"
  "Canepro:central-observability-hub-stack:Central Observability Hub Stack"
)

echo "📦 Setting up jobs for the following repositories:"
for repo in "${REPOS[@]}"; do
  IFS=':' read -r owner name desc <<< "$repo"
  echo "  - ${owner}/${name}: ${desc}"
done
echo ""

# Create jobs for each repository
for repo in "${REPOS[@]}"; do
  IFS=':' read -r owner name desc <<< "$repo"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Setting up jobs for ${owner}/${name}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Create version-check job
  echo "1️⃣ Creating version-check job..."
  bash .jenkins/create-version-check-job.sh "$owner" "$name" "version-check-${name}" || {
    echo "⚠️  Failed to create version-check job for ${name}"
  }
  echo ""
  
  # Create security-validation job
  echo "2️⃣ Creating security-validation job..."
  bash .jenkins/create-security-validation-job.sh "$owner" "$name" "security-validation-${name}" || {
    echo "⚠️  Failed to create security-validation job for ${name}"
  }
  echo ""
  
  echo "✅ Completed setup for ${owner}/${name}"
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All jobs created successfully!"
echo ""
echo "📋 Summary:"
echo ""
for repo in "${REPOS[@]}"; do
  IFS=':' read -r owner name desc <<< "$repo"
  echo "  ${owner}/${name}:"
  echo "    - version-check-${name}"
  echo "    - security-validation-${name}"
done
echo ""
echo "🔗 View jobs at: ${JENKINS_URL}"
echo ""
