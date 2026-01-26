#!/bin/bash
# Script to automatically update VERSIONS.md with new versions
# This is called by the version-check pipeline when creating PRs

set -euo pipefail

VERSIONS_FILE="${VERSIONS_FILE:-VERSIONS.md}"
UPDATE_TYPE="${1:-}"  # "terraform", "image", "chart", etc.
COMPONENT="${2:-}"    # Component name
CURRENT_VERSION="${3:-}"
NEW_VERSION="${4:-}"
LOCATION="${5:-}"     # File location

if [ ! -f "$VERSIONS_FILE" ]; then
  echo "❌ VERSIONS.md not found"
  exit 1
fi

# Function to update version in VERSIONS.md table
update_version_in_table() {
  local component="$1"
  local current="$2"
  local latest="$3"
  local location="$4"
  
  # Update the "Current Version" column for the component
  # This uses sed to find the row and update it
  sed -i "s/| \*\*${component}\*\* | \`${current}\` |/| **${component}** | \`${latest}\` |/g" "$VERSIONS_FILE" || true
  
  # Update the "Latest Version" column
  sed -i "s/| \*\*${component}\*\* | \`[^\`]*\` | \`[^\`]*\` |/| **${component}** | \`${latest}\` | \`${latest}\` |/g" "$VERSIONS_FILE" || true
  
  # Update upgrade status
  sed -i "s/| \*\*${component}\*\* |.*| ⚠️ \*\*Can upgrade\*\*/| **${component}** | \`${latest}\` | \`${latest}\` | ✅ **Up to date**/g" "$VERSIONS_FILE" || true
}

# Function to update version in actual code files
update_version_in_code() {
  local location="$1"
  local current="$2"
  local new_version="$3"
  
  if [ -f "$location" ]; then
    # Update version in the file
    case "$location" in
      terraform/main.tf)
        # Update Terraform provider version
        sed -i "s/version = \"${current}\"/version = \"~> ${new_version}\"/g" "$location" || true
        ;;
      values.yaml)
        # Update image tag
        sed -i "s/tag: \"${current}\"/tag: \"${new_version}\"/g" "$location" || true
        # Update chart version comment
        sed -i "s/Chart:.*${current}/Chart: ${new_version}/g" "$location" || true
        ;;
      ops/manifests/*.yaml)
        # Update container image tag
        sed -i "s/image:.*:${current}/image:.*:${new_version}/g" "$location" || true
        ;;
    esac
  fi
}

# Main update logic
case "$UPDATE_TYPE" in
  terraform)
    update_version_in_table "$COMPONENT" "$CURRENT_VERSION" "$NEW_VERSION" "$LOCATION"
    update_version_in_code "$LOCATION" "$CURRENT_VERSION" "$NEW_VERSION"
    ;;
  image)
    update_version_in_table "$COMPONENT" "$CURRENT_VERSION" "$NEW_VERSION" "$LOCATION"
    update_version_in_code "$LOCATION" "$CURRENT_VERSION" "$NEW_VERSION"
    ;;
  chart)
    update_version_in_table "$COMPONENT" "$CURRENT_VERSION" "$NEW_VERSION" "$LOCATION"
    # Chart versions are usually in ArgoCD app files, handle separately
    ;;
  *)
    echo "Unknown update type: $UPDATE_TYPE"
    exit 1
    ;;
esac

echo "✅ Updated $COMPONENT from $CURRENT_VERSION to $NEW_VERSION in $VERSIONS_FILE and $LOCATION"
