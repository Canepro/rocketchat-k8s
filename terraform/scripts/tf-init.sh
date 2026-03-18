#!/bin/bash
# Terraform initialization helper
# This script initializes the main AKS stack with the local backend.hcl file.
#
# Usage:
#   ./scripts/tf-init.sh
#   OR
#   bash scripts/tf-init.sh
#
# Prerequisites:
#   1. Create backend.hcl from terraform/bootstrap output or backend.hcl.example
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
    echo "   1. Create backend.hcl from bootstrap outputs:"
    echo "      cd bootstrap && terraform output -raw backend_hcl > ../backend.hcl && cd .."
    echo ""
    echo "   2. Or copy the example and fill it manually:"
    echo "      cp backend.hcl.example backend.hcl"
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
