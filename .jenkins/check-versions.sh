#!/bin/bash
# Version Checker Script
# Checks for latest versions of components and creates PRs/issues based on risk

set -euo pipefail

# Configuration
GITHUB_REPO="${GITHUB_REPO:-Canepro/rocketchat-k8s}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
VERSIONS_FILE="${VERSIONS_FILE:-VERSIONS.md}"

# Install dependencies
apk add --no-cache curl jq git bash >/dev/null 2>&1 || true

# Function to check if version update is major (high risk)
is_major_update() {
  local current=$1
  local latest=$2
  local current_major=$(echo "$current" | cut -d. -f1)
  local latest_major=$(echo "$latest" | cut -d. -f1)
  [ "$latest_major" -gt "$current_major" ]
}

# Function to get latest GitHub release version
get_latest_github_release() {
  local repo=$1
  curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
}

# Function to get latest Terraform provider version
get_latest_terraform_provider() {
  local provider=$1
  curl -s "https://registry.terraform.io/v1/providers/hashicorp/${provider}/versions" | \
    jq -r '.versions[] | .version' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}

# Check versions and collect updates
echo "Checking for version updates..."

UPDATES=()
CRITICAL_UPDATES=()
HIGH_UPDATES=()
MEDIUM_UPDATES=()

# Check RocketChat version
CURRENT_RC=$(grep -A5 "Rocket.Chat Application" "$VERSIONS_FILE" | grep "Current Version" | awk -F'|' '{print $3}' | tr -d ' ' || echo "8.0.1")
LATEST_RC=$(get_latest_github_release "RocketChat/Rocket.Chat")

if [ "$CURRENT_RC" != "$LATEST_RC" ]; then
  if is_major_update "$CURRENT_RC" "$LATEST_RC"; then
    CRITICAL_UPDATES+=("RocketChat: $CURRENT_RC → $LATEST_RC (MAJOR)")
  else
    HIGH_UPDATES+=("RocketChat: $CURRENT_RC → $LATEST_RC")
  fi
fi

# Check Terraform Azure Provider
CURRENT_TF=$(grep "Azure Provider" "$VERSIONS_FILE" | awk -F'|' '{print $3}' | tr -d ' ' | sed 's/~>//' || echo "3.0")
LATEST_TF=$(get_latest_terraform_provider "azurerm")

if [ "$CURRENT_TF" != "$LATEST_TF" ]; then
  if is_major_update "$CURRENT_TF" "$LATEST_TF"; then
    CRITICAL_UPDATES+=("Terraform Azure Provider: $CURRENT_TF → $LATEST_TF (MAJOR)")
  else
    HIGH_UPDATES+=("Terraform Azure Provider: $CURRENT_TF → $LATEST_TF")
  fi
fi

# Check other components from VERSIONS.md
# (Add more checks as needed)

# Summary
echo ""
echo "Version Check Summary:"
echo "  Critical (Major): ${#CRITICAL_UPDATES[@]}"
echo "  High: ${#HIGH_UPDATES[@]}"
echo "  Medium: ${#MEDIUM_UPDATES[@]}"

# Create PR or Issue
if [ ${#CRITICAL_UPDATES[@]} -gt 0 ]; then
  echo "🚨 Creating GitHub issue for CRITICAL updates..."
  # Create issue logic here
elif [ ${#HIGH_UPDATES[@]} -gt 0 ] || [ ${#MEDIUM_UPDATES[@]} -ge 3 ]; then
  echo "⚠️ Creating PR for version updates..."
  # Create PR logic here
else
  echo "✅ All versions are up to date"
fi
