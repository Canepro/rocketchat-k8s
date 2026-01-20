#!/bin/sh
# Cleanup script for stale pods after cluster auto-shutdown/restart
# This script removes orphaned pods that are left in terminal states after AKS cluster restarts
set -eu

echo "[$(date -Iseconds)] Starting stale pod cleanup..."

# Function to safely delete pods by phase
cleanup_by_phase() {
  local phase=$1
  local description=$2
  
  echo "Checking for $description pods (status.phase=$phase)..."
  
  # Get count first
  count=$(kubectl get pods -A --field-selector=status.phase="$phase" --no-headers 2>/dev/null | wc -l)
  
  if [ "$count" -gt 0 ]; then
    echo "Found $count $description pods. Cleaning up..."
    kubectl get pods -A --field-selector=status.phase="$phase" --no-headers
    kubectl delete pods -A --field-selector=status.phase="$phase" --wait=false
    echo "Deleted $count $description pods."
  else
    echo "No $description pods found."
  fi
}

# Clean up terminal state pods
cleanup_by_phase "Succeeded" "Completed"
cleanup_by_phase "Failed" "Failed/Error"
cleanup_by_phase "Unknown" "ContainerStatusUnknown"

echo "[$(date -Iseconds)] Stale pod cleanup complete."
echo ""
echo "Current pod status summary:"
kubectl get pods -A --no-headers | awk '{print $4}' | sort | uniq -c
