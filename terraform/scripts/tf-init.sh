#!/bin/bash
# Terraform Initialization Script for Cloud Shell
# This script helps initialize Terraform with backend configuration in ephemeral Cloud Shell sessions.
#
# Usage:
#   ./scripts/tf-init.sh
#   OR
#   bash scripts/tf-init.sh
#
# Prerequisites:
#   1. Copy backend.hcl.example to backend.hcl and update with your values
#   2. Ensure you're authenticated: az login
#   3. Ensure you're in the terraform/ directory

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if backend.hcl exists
if [ ! -f "$TERRAFORM_DIR/backend.hcl" ]; then
    echo "❌ Error: backend.hcl not found!"
    echo ""
    echo "📝 To fix this:"
    echo "   1. Copy backend.hcl.example to backend.hcl:"
    echo "      cp backend.hcl.example backend.hcl"
    echo ""
    echo "   2. Edit backend.hcl with your actual storage account details:"
    echo "      nano backend.hcl"
    echo ""
    echo "   3. Run this script again:"
    echo "      ./scripts/tf-init.sh"
    exit 1
fi

# Change to terraform directory
cd "$TERRAFORM_DIR"

echo "🔧 Initializing Terraform with backend configuration..."
echo ""

# Initialize Terraform with backend config
terraform init -reconfigure -backend-config=backend.hcl

echo ""
echo "✅ Terraform initialized successfully!"
echo ""
echo "📋 Next steps:"
echo "   terraform plan    # Review changes"
echo "   terraform apply   # Apply changes"
echo ""
