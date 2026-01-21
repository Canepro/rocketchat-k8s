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
CRUMB=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

if [ -z "$CRUMB" ] || [[ "$CRUMB" == *"Error"* ]] || [[ "$CRUMB" == *"401"* ]]; then
  echo "❌ Failed to get CSRF token. Check credentials."
  echo "CRUMB response: $CRUMB"
  exit 1
fi

echo "✅ CSRF token obtained"

# Check if job already exists
echo "Checking if job already exists..."
EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "$CRUMB" \
  "$JENKINS_URL/job/$JOB_NAME/api/json")

if [ "$EXISTS" = "200" ]; then
  echo "⚠️  Job '$JOB_NAME' already exists. Deleting it first..."
  curl -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -H "$CRUMB" \
    "$JENKINS_URL/job/$JOB_NAME/doDelete"
  echo "✅ Old job deleted"
fi

# Create job
echo "Creating job: $JOB_NAME"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "$CRUMB" \
  -H "Content-Type: application/xml" \
  --data-binary @"$CONFIG_FILE" \
  "$JENKINS_URL/createItem?name=$JOB_NAME")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Job created successfully!"
  
  # Trigger scan
  echo "Triggering initial scan..."
  SCAN_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -H "$CRUMB" \
    "$JENKINS_URL/job/$JOB_NAME/scan")
  
  if [ "$SCAN_CODE" = "200" ] || [ "$SCAN_CODE" = "201" ]; then
    echo "✅ Initial scan triggered!"
    echo ""
    echo "Job URL: $JENKINS_URL/job/$JOB_NAME"
    echo "Check job status in Jenkins UI or wait a few moments for the scan to complete."
  else
    echo "⚠️  Scan trigger returned HTTP $SCAN_CODE (job was created but scan may have failed)"
  fi
else
  echo "❌ Failed to create job. HTTP Status: $HTTP_CODE"
  echo "Check Jenkins logs or try accessing the UI to see detailed error messages."
  exit 1
fi
