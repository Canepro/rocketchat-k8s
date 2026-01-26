#!/bin/bash
# Script to create the security-validation Jenkins job
# This creates a scheduled Pipeline job (not multibranch) that runs daily
# Usage: bash create-security-validation-job.sh [repo-owner] [repo-name] [job-name]

set -euo pipefail

# Configuration with defaults
REPO_OWNER="${1:-Canepro}"
REPO_NAME="${2:-rocketchat-k8s}"
JOB_NAME="${3:-security-validation-${REPO_NAME}}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
CONFIG_FILE="${CONFIG_FILE:-.jenkins/security-validation-job-config.xml}"
JENKINS_USER="${JENKINS_USER:-}"

# Cookie jar for session management
COOKIE_JAR="$(mktemp -t jenkins-cookies.XXXXXX)"
cleanup() {
  rm -f "$COOKIE_JAR" 2>/dev/null || true
}
trap cleanup EXIT

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

# Check if job already exists
echo "Checking if job already exists..."
EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  "$JENKINS_URL/job/$JOB_NAME/api/json")

if [ "$EXISTS" = "200" ]; then
  echo "⚠️  Job '$JOB_NAME' already exists. Deleting it first..."
  curl -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -H "$CRUMB_FIELD:$CRUMB_VALUE" \
    "$JENKINS_URL/job/$JOB_NAME/doDelete"
  echo "✅ Old job deleted"
fi

# Create temporary config file with repository-specific values
TEMP_CONFIG=$(mktemp -t security-validation-config.XXXXXX.xml)
trap "rm -f $TEMP_CONFIG" EXIT

# Generate config from template, replacing repository values
sed "s|https://github.com/Canepro/rocketchat-k8s|https://github.com/${REPO_OWNER}/${REPO_NAME}|g" \
    "$CONFIG_FILE" > "$TEMP_CONFIG"

# Verify temp config file exists
if [ ! -f "$TEMP_CONFIG" ]; then
  echo "❌ Failed to create temporary config file"
  exit 1
fi

echo "Using config file: $CONFIG_FILE (customized for ${REPO_OWNER}/${REPO_NAME})"

# Create job
echo "Creating job: $JOB_NAME for repository ${REPO_OWNER}/${REPO_NAME}"
RESPONSE=$(curl -sS -L -w "\n%{http_code}" -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  -H "Content-Type: application/xml" \
  --data-binary @"$TEMP_CONFIG" \
  "$JENKINS_URL/createItem?name=$JOB_NAME")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Job created successfully!"
  echo ""
  echo "Job URL: $JENKINS_URL/job/$JOB_NAME"
  echo "Repository: ${REPO_OWNER}/${REPO_NAME}"
  echo ""
  echo "The job is scheduled to run weekdays at 6 PM (after cluster starts at 4 PM)."
  echo "You can trigger it manually from the Jenkins UI or run:"
  echo "  curl -X POST -u \"\$JENKINS_USER:****\" \"$JENKINS_URL/job/$JOB_NAME/build\""
else
  echo "❌ Failed to create job. HTTP Status: $HTTP_CODE"
  if [ -n "$RESPONSE_BODY" ]; then
    echo "Response body:"
    echo "$RESPONSE_BODY"
  fi
  exit 1
fi
