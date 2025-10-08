#!/bin/bash
# Fix kubectl access for non-root user

echo "🔧 Setting up kubectl access..."

# Create .kube directory if it doesn't exist
mkdir -p ~/.kube

# Copy k3s config to user's .kube directory
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Change ownership to current user
sudo chown $(id -u):$(id -g) ~/.kube/config

# Set proper permissions
chmod 600 ~/.kube/config

# Export KUBECONFIG
export KUBECONFIG=~/.kube/config

echo "✅ kubectl access configured!"
echo ""
echo "Run this command to make it permanent:"
echo "echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc"
echo "source ~/.bashrc"
echo ""
echo "Test with: kubectl get nodes"

