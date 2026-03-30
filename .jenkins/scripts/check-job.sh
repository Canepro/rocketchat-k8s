#!/bin/bash
# Quick script to check if Jenkins job exists and its status

set -euo pipefail

# Configuration
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
JOB_NAME="${JOB_NAME:-rocketchat-k8s}"
JENKINS_USER="${JENKINS_USER:-}"

get_jenkins_secret_value() {
  local primary_key="$1"
  local legacy_key="$2"
  local value

  value=$(kubectl get secret jenkins-admin-credentials -n jenkins -o "jsonpath={.data.${primary_key}}" 2>/dev/null | base64 -d || true)
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  kubectl get secret jenkins-admin -n jenkins -o "jsonpath={.data.${legacy_key}}" 2>/dev/null | base64 -d || true
}

# Get Jenkins credentials from Kubernetes secret (unless provided via env)
if [ -z "${JENKINS_USER}" ]; then
  JENKINS_USER=$(get_jenkins_secret_value admin-user username)
fi

JENKINS_PASSWORD="${JENKINS_PASSWORD:-}"
if [ -z "${JENKINS_PASSWORD}" ]; then
  JENKINS_PASSWORD=$(get_jenkins_secret_value admin-password password)
fi

if [ -z "${JENKINS_USER}" ] || [ -z "${JENKINS_PASSWORD}" ]; then
  echo "❌ Failed to get Jenkins credentials from Kubernetes secret"
  echo "Please provide credentials manually:"
  if [ -z "${JENKINS_USER}" ]; then
    read -r -p "Jenkins username: " JENKINS_USER
  fi
  if [ -z "${JENKINS_PASSWORD}" ]; then
    read -rs -p "Jenkins password/token: " JENKINS_PASSWORD
    echo ""
  fi
fi

echo "Checking if job '$JOB_NAME' exists..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/$JOB_NAME/api/json")

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Job '$JOB_NAME' exists!"
  echo ""
  echo "Getting job details..."
  JOB_INFO=$(curl -s \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    "$JENKINS_URL/job/$JOB_NAME/api/json?pretty=true")

  echo "$JOB_INFO" | grep -E "(name|url|color|healthReport)" | head -10
  echo ""
  echo "Job URL: $JENKINS_URL/job/$JOB_NAME"
  echo ""
  echo "To view in browser:"
  echo "  $JENKINS_URL/job/$JOB_NAME"
else
  echo "❌ Job '$JOB_NAME' does not exist (HTTP $HTTP_CODE)"
  echo ""
  echo "To create the job, run:"
  echo "  bash .jenkins/scripts/create-job.sh"
fi
