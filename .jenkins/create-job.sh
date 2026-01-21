#!/bin/bash
# Quick script to create Jenkins Multibranch Pipeline job via CLI
# Handles CSRF token automatically

set -e

# Configuration
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
JOB_NAME="${JOB_NAME:-rocketchat-k8s}"
CONFIG_FILE="${CONFIG_FILE:-.jenkins/job-config.xml}"
JENKINS_USER="${JENKINS_USER:-admin}"

# Get Jenkins password from Kubernetes secret
echo "Getting Jenkins admin password from Kubernetes secret..."
JENKINS_PASSWORD=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

if [ -z "$JENKINS_PASSWORD" ]; then
  echo "❌ Failed to get Jenkins password from Kubernetes secret"
  echo "Please provide password manually:"
  read -rs JENKINS_PASSWORD
fi

# Get CSRF token (required when CSRF protection is enabled)
echo "Getting CSRF token..."
# Use JSON endpoint for more reliable parsing
CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/crumbIssuer/api/json")

if [ -z "$CRUMB_JSON" ] || [[ "$CRUMB_JSON" == *"Error"* ]] || [[ "$CRUMB_JSON" == *"401"* ]] || [[ "$CRUMB_JSON" == *"403"* ]]; then
  echo "❌ Failed to get CSRF token. Check credentials."
  echo "Response: $CRUMB_JSON"
  exit 1
fi

# Parse JSON response to extract crumb field and value
CRUMB_FIELD=$(echo "$CRUMB_JSON" | grep -o '"crumbRequestField":"[^"]*"' | cut -d'"' -f4)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)

if [ -z "$CRUMB_FIELD" ] || [ -z "$CRUMB_VALUE" ]; then
  echo "❌ Failed to parse CSRF token from JSON response"
  echo "Response: $CRUMB_JSON"
  exit 1
fi

echo "✅ CSRF token obtained: $CRUMB_FIELD:****"

# Check if job already exists
echo "Checking if job already exists..."
EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  "$JENKINS_URL/job/$JOB_NAME/api/json")

if [ "$EXISTS" = "200" ]; then
  echo "⚠️  Job '$JOB_NAME' already exists. Deleting it first..."
  curl -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -H "$CRUMB_FIELD:$CRUMB_VALUE" \
    "$JENKINS_URL/job/$JOB_NAME/doDelete"
  echo "✅ Old job deleted"
fi

# Verify config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config file not found: $CONFIG_FILE"
  exit 1
fi

echo "Using config file: $CONFIG_FILE ($(wc -c < "$CONFIG_FILE") bytes)"

# Create job
echo "Creating job: $JOB_NAME"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  -H "Content-Type: application/xml" \
  --data-binary @"$CONFIG_FILE" \
  "$JENKINS_URL/createItem?name=$JOB_NAME")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Job created successfully!"
  
  # Trigger scan
  echo "Triggering initial scan..."
  SCAN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -H "$CRUMB_FIELD:$CRUMB_VALUE" \
    "$JENKINS_URL/job/$JOB_NAME/scan")
  
  SCAN_CODE=$(echo "$SCAN_RESPONSE" | tail -n1)
  
  if [ "$SCAN_CODE" = "200" ] || [ "$SCAN_CODE" = "201" ]; then
    echo "✅ Initial scan triggered!"
    echo ""
    echo "Job URL: $JENKINS_URL/job/$JOB_NAME"
    echo "Check job status in Jenkins UI or wait a few moments for the scan to complete."
  else
    echo "⚠️  Scan trigger returned HTTP $SCAN_CODE (job was created but scan may have failed)"
    echo "Response: $(echo "$SCAN_RESPONSE" | head -n-1)"
  fi
else
  echo "❌ Failed to create job. HTTP Status: $HTTP_CODE"
  if [ -n "$RESPONSE_BODY" ]; then
    echo "Response body:"
    echo "$RESPONSE_BODY"
  fi
  echo ""
  echo "Troubleshooting:"
  echo "1. Check if job already exists: curl -u \"$JENKINS_USER:****\" \"$JENKINS_URL/job/$JOB_NAME/api/json\""
  echo "2. Check Jenkins logs: kubectl logs -n jenkins jenkins-0 -c jenkins --tail=50"
  echo "3. Verify XML config is valid: cat $CONFIG_FILE | head -20"
  exit 1
fi
