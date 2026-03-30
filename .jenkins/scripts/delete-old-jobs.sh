#!/bin/bash
# Script to delete old Jenkins jobs that have been replaced by repository-specific versions
# Usage: bash delete-old-jobs.sh

set -euo pipefail

# Configuration
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
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

# Jobs to delete (old versions without repository suffixes)
OLD_JOBS=(
  "version-check"
  "security-validation"
)

# Cookie jar for session management
COOKIE_JAR="$(mktemp -t jenkins-cookies.XXXXXX)"
cleanup() {
  rm -f "$COOKIE_JAR" 2>/dev/null || true
}
trap cleanup EXIT

# Get Jenkins credentials from Kubernetes secret
echo "Getting Jenkins admin credentials from Kubernetes secret..."
if [ -z "${JENKINS_USER}" ]; then
  JENKINS_USER=$(get_jenkins_secret_value admin-user username)
fi

JENKINS_PASSWORD="${JENKINS_PASSWORD:-}"
if [ -z "${JENKINS_PASSWORD}" ]; then
  JENKINS_PASSWORD=$(get_jenkins_secret_value admin-password password)
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
echo ""

# Delete old jobs
echo "🗑️  Deleting old Jenkins jobs..."
echo ""

for job in "${OLD_JOBS[@]}"; do
  echo "Checking job: $job"

  # Check if job exists
  EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -H "$CRUMB_FIELD:$CRUMB_VALUE" \
    "$JENKINS_URL/job/$job/api/json")

  if [ "$EXISTS" = "200" ]; then
    echo "  Deleting: $job"
    DELETE_RESPONSE=$(curl -sS -L -w "\n%{http_code}" -X POST \
      -u "$JENKINS_USER:$JENKINS_PASSWORD" \
      -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
      -H "$CRUMB_FIELD:$CRUMB_VALUE" \
      "$JENKINS_URL/job/$job/doDelete")

    HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
      echo "  ✅ Deleted: $job"
    else
      echo "  ⚠️  Failed to delete $job (HTTP $HTTP_CODE)"
    fi
  else
    echo "  ℹ️  Job $job does not exist (skipping)"
  fi
  echo ""
done

echo "✅ Cleanup complete!"
echo ""
echo "Remaining repository-specific jobs:"
echo "  - version-check-rocketchat-k8s"
echo "  - version-check-central-observability-hub-stack"
echo "  - security-validation-rocketchat-k8s"
echo "  - security-validation-central-observability-hub-stack"
