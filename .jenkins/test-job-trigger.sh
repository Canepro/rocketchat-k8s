#!/bin/bash
# Script to test triggering a Jenkins job
# Usage: bash test-job-trigger.sh [job-name]

set -euo pipefail

JOB_NAME="${1:-version-check-rocketchat-k8s}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
JENKINS_USER="${JENKINS_USER:-}"

# Get Jenkins credentials from Kubernetes secret
echo "Getting Jenkins admin credentials from Kubernetes secret..."
if [ -z "${JENKINS_USER}" ]; then
  JENKINS_USER=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || true)
fi

JENKINS_PASSWORD="${JENKINS_PASSWORD:-}"
if [ -z "${JENKINS_PASSWORD}" ]; then
  JENKINS_PASSWORD=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
fi

if [ -z "${JENKINS_USER}" ] || [ -z "${JENKINS_PASSWORD}" ]; then
  echo "❌ Failed to get Jenkins credentials from Kubernetes secret"
  if [ -z "${JENKINS_USER}" ]; then
    echo "Please provide username manually:"
    read -r JENKINS_USER
  fi
  if [ -z "${JENKINS_PASSWORD}" ]; then
    echo "Please provide password (or API token) manually:"
    read -rs JENKINS_PASSWORD
    echo ""
  fi
fi

# Cookie jar for session management
COOKIE_JAR="$(mktemp -t jenkins-cookies.XXXXXX)"
cleanup() {
  rm -f "$COOKIE_JAR" 2>/dev/null || true
}
trap cleanup EXIT

# Get CSRF token
echo "Getting CSRF token..."
CRUMB_JSON=$(curl -sS -L \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  "$JENKINS_URL/crumbIssuer/api/json")

if [ -z "$CRUMB_JSON" ] || echo "$CRUMB_JSON" | grep -q "Error\|401\|403"; then
  echo "❌ Failed to get CSRF token. Check credentials."
  exit 1
fi

if command -v jq &> /dev/null; then
  CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField')
  CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb')
else
  CRUMB_FIELD=$(echo "$CRUMB_JSON" | grep -o '"crumbRequestField":"[^"]*"' | cut -d'"' -f4)
  CRUMB_VALUE=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$CRUMB_FIELD" ] || [ -z "$CRUMB_VALUE" ] || [ "$CRUMB_FIELD" = "null" ] || [ "$CRUMB_VALUE" = "null" ]; then
  echo "❌ Failed to parse CSRF token"
  exit 1
fi

echo "✅ CSRF token obtained"
echo "Triggering job: $JOB_NAME"
echo "Jenkins URL: $JENKINS_URL"
echo ""

RESPONSE=$(curl -sS -L -w "\n%{http_code}" -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  "$JENKINS_URL/job/$JOB_NAME/build")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "302" ]; then
  echo "✅ Job triggered successfully!"
  echo ""
  echo "Job URL: $JENKINS_URL/job/$JOB_NAME"
  echo ""
  echo "Monitor the job at:"
  echo "  $JENKINS_URL/job/$JOB_NAME"
  echo ""
  echo "Or check build queue:"
  echo "  $JENKINS_URL/queue"
else
  echo "❌ Failed to trigger job. HTTP Status: $HTTP_CODE"
  if [ -n "$RESPONSE_BODY" ]; then
    echo "Response:"
    echo "$RESPONSE_BODY" | head -20
  fi
  exit 1
fi
