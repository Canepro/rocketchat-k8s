#!/bin/bash
# Rocket.Chat Kubernetes Deployment Script
# Use with caution - review each section before running

set -e  # Exit on error

echo "🚀 Rocket.Chat Enterprise Deployment Script"
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
function info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function check_command() {
    if ! command -v $1 &> /dev/null; then
        error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# Pre-flight checks
info "Running pre-flight checks..."
check_command kubectl
check_command helm

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster"
    exit 1
fi

info "✅ Cluster connection verified"
info "Node: $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"

# Step 1: Storage
echo ""
info "Step 1: Deploying Storage (PV + PVC)..."
kubectl apply -f persistent-volumes.yaml
sleep 2
kubectl apply -f mongo-pvc.yaml
sleep 2

info "Verifying PV/PVC binding..."
kubectl get pv
kubectl get pvc -n rocketchat

read -p "Press Enter to continue to Step 2 (Ingress Controller)..."

# Step 2: Ingress
echo ""
info "Step 2: Deploying NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

info "Waiting for ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

info "✅ Ingress controller ready"

read -p "Press Enter to continue to Step 3 (cert-manager)..."

# Step 3: cert-manager
echo ""
info "Step 3: Deploying cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml

info "Waiting for cert-manager to be ready..."
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=300s

info "✅ cert-manager ready"

read -p "Press Enter to continue to Step 4 (ClusterIssuer)..."

# Step 4: ClusterIssuer
echo ""
info "Step 4: Applying ClusterIssuer..."
kubectl apply -f clusterissuer.yaml
sleep 2

kubectl get clusterissuer

read -p "Press Enter to continue to Step 5 (Prometheus Agent)..."

# Step 5: Prometheus Agent
echo ""
warn "Step 5: Prometheus Agent deployment"
warn "⚠️  Make sure you've updated Grafana Cloud credentials in prometheus-agent.yaml"
read -p "Have you updated Grafana Cloud credentials? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl apply -f prometheus-agent.yaml
    info "✅ Prometheus agent deployed"
    sleep 2
    kubectl get pods -n monitoring
else
    warn "Skipping Prometheus agent deployment"
fi

read -p "Press Enter to continue to Step 6 (SMTP Secret)..."

# Step 6: SMTP Secret
echo ""
warn "Step 6: SMTP Secret creation"
read -p "Enter your SMTP password: " -s SMTP_PASSWORD
echo

if [ ! -z "$SMTP_PASSWORD" ]; then
    kubectl create secret generic smtp-credentials -n rocketchat \
      --from-literal=password="$SMTP_PASSWORD" \
      --dry-run=client -o yaml | kubectl apply -f -
    info "✅ SMTP secret created"
else
    warn "No password provided, skipping secret creation"
fi

read -p "Press Enter to continue to Step 7 (Helm Repo)..."

# Step 7: Helm Repo
echo ""
info "Step 7: Adding Rocket.Chat Helm repository..."
helm repo add rocketchat https://rocketchat.github.io/helm-charts
helm repo update

info "✅ Helm repo added"

read -p "Press Enter to continue to Step 8 (Deploy Rocket.Chat)..."

# Step 8: Deploy Rocket.Chat
echo ""
info "Step 8: Deploying Rocket.Chat..."
info "Pre-deployment verification:"

# Check prerequisites
echo "Checking prerequisites..."
kubectl get pvc -n rocketchat | grep mongo-pvc
kubectl get clusterissuer | grep production-cert-issuer
kubectl get secret -n rocketchat | grep smtp-credentials

echo ""
warn "About to deploy Rocket.Chat with the following configuration:"
echo "  - Image: 7.10.0"
echo "  - Replicas: 2"
echo "  - Domain: k8.canepro.me"
echo "  - Microservices: Enabled"
echo "  - NATS: Enabled"
echo "  - MongoDB: Persistent (mongo-pvc)"
echo ""
read -p "Proceed with deployment? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    helm install rocketchat -f values.yaml rocketchat/rocketchat -n rocketchat
    
    info "✅ Rocket.Chat deployed!"
    info "Monitoring deployment progress..."
    
    sleep 5
    kubectl get pods -n rocketchat
    
    echo ""
    info "To watch deployment progress, run:"
    echo "  kubectl get pods -n rocketchat -w"
    echo ""
    info "To check certificate status:"
    echo "  kubectl get certificate -n rocketchat"
    echo ""
    info "Once ready, access Rocket.Chat at:"
    echo "  https://k8.canepro.me"
else
    warn "Deployment cancelled"
fi

echo ""
info "🎉 Deployment script completed!"
info "See docs/deployment-checklist.md for verification steps"

