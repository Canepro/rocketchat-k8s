#!/bin/bash
set -e

echo "============================================"
echo "🚀 Rocket.Chat k3s Lab Deployment Script"
echo "============================================"
echo "Deploying Rocket.Chat with:"
echo "  • Traefik Ingress (k3s native)"
echo "  • Enterprise microservices"
echo "  • Grafana Cloud monitoring"
echo "  • Let's Encrypt TLS certificates"
echo ""

# Prerequisites check
echo "🔍 Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ helm not found. Please install Helm v3."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster. Check your kubeconfig."
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Check if Grafana Cloud secret exists
if ! kubectl get secret grafana-cloud-secret -n monitoring &> /dev/null; then
    echo "⚠️  WARNING: Grafana Cloud secret not found!"
    echo "   Please create it first:"
    echo "   1. cp grafana-cloud-secret.yaml.template grafana-cloud-secret.yaml"
    echo "   2. Edit grafana-cloud-secret.yaml with your credentials"
    echo "   3. kubectl apply -f grafana-cloud-secret.yaml"
    echo ""
    read -p "Do you want to continue without monitoring? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SKIP_MONITORING=true
else
    echo "✅ Grafana Cloud secret found"
    SKIP_MONITORING=false
fi
echo ""

# Step 1: Check Traefik (k3s native ingress)
echo "🌐 Step 1: Checking Traefik ingress (k3s native)..."
if kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik &> /dev/null; then
    echo "✅ Traefik ingress controller found (k3s native)"
else
    echo "⚠️  Traefik not found. This script is designed for k3s with Traefik."
    echo "   If you're using a different cluster, please install Traefik or update the ingress configuration."
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# Step 2: Install cert-manager
echo "🔒 Step 2: Installing cert-manager..."
if ! kubectl get namespace cert-manager &> /dev/null; then
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
    echo "⏳ Waiting for cert-manager..."
    kubectl wait --namespace cert-manager \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/instance=cert-manager \
      --timeout=300s || true
else
    echo "ℹ️  cert-manager already installed"
fi
echo "✅ cert-manager ready"
echo ""

# Step 3: Apply ClusterIssuer
echo "📜 Step 3: Creating Let's Encrypt ClusterIssuer (Traefik compatible)..."
kubectl apply -f clusterissuer.yaml
sleep 5
kubectl get clusterissuer
echo "✅ ClusterIssuer created"
echo ""

# Step 4: Add Helm repositories
echo "📦 Step 4: Adding Helm repositories..."
helm repo add rocketchat https://rocketchat.github.io/helm-charts 2>/dev/null || true
if [[ "$SKIP_MONITORING" == "false" ]]; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
fi
helm repo update
echo "✅ Helm repositories ready"
echo ""

# Step 5: Create SMTP secret
echo "📧 Step 5: Creating SMTP secret..."
kubectl create namespace rocketchat --dry-run=client -o yaml | kubectl apply -f -
echo "⚠️  Please enter your Mailgun SMTP password (or press Enter to skip):"
read -s SMTP_PASSWORD
if [[ -n "$SMTP_PASSWORD" ]]; then
    kubectl create secret generic smtp-credentials -n rocketchat \
      --from-literal=password="$SMTP_PASSWORD" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ SMTP secret created"
else
    echo "⏸️  SMTP secret skipped (you can create it later)"
fi
echo ""

# Step 6: Deploy Rocket.Chat
echo "🚀 Step 6: Deploying Rocket.Chat Enterprise..."
helm upgrade --install rocketchat rocketchat/rocketchat \
  --namespace rocketchat --create-namespace \
  -f values.yaml
echo "✅ Rocket.Chat deployed with microservices enabled"
echo ""

# Step 7: Deploy monitoring (if not skipped)
if [[ "$SKIP_MONITORING" == "false" ]]; then
    echo "📊 Step 7: Deploying Prometheus Agent with Grafana Cloud..."
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
      --namespace monitoring \
      -f values-monitoring.yaml
    echo "✅ Monitoring stack deployed"
else
    echo "⏸️  Step 7: Monitoring deployment skipped"
fi
echo ""

# Step 8: Wait and verify deployment
echo "⏳ Waiting for Rocket.Chat deployment to stabilize..."
kubectl rollout status deployment/rocketchat -n rocketchat --timeout=300s
echo ""

echo "📊 Checking deployment status..."
kubectl get pods -n rocketchat
if [[ "$SKIP_MONITORING" == "false" ]]; then
    kubectl get pods -n monitoring
fi
echo ""

# Step 9: Verification
echo "============================================"
echo "✅ DEPLOYMENT COMPLETE!"
echo "============================================"
echo ""
echo "🏗️  **Deployed Components:**"
echo "  • Rocket.Chat Enterprise (microservices mode)"
echo "  • MongoDB ReplicaSet"
echo "  • NATS messaging"
echo "  • Traefik ingress with TLS"
if [[ "$SKIP_MONITORING" == "false" ]]; then
    echo "  • Prometheus Agent → Grafana Cloud"
fi
echo ""
echo "📊 **Status Check Commands:**"
echo ""
echo "# Check Rocket.Chat pods:"
echo "kubectl get pods -n rocketchat"
echo ""
echo "# Check TLS certificate (may take 2-5 minutes):"
echo "kubectl get certificate -n rocketchat"
echo "kubectl describe certificate rocketchat-tls -n rocketchat"
echo ""
echo "# Check ingress and services:"
echo "kubectl get ingress,svc -n rocketchat"
echo ""
if [[ "$SKIP_MONITORING" == "false" ]]; then
    echo "# Check monitoring stack:"
    echo "kubectl get pods -n monitoring"
    echo ""
    echo "# Check Grafana Cloud connectivity:"
    echo "kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus"
fi
echo ""
echo "🌐 **Access Instructions:**"
echo ""
echo "1. Wait for certificate to be ready (check with above commands)"
echo "2. Access Rocket.Chat at: https://k8.canepro.me"
echo "3. Complete initial setup (create admin user)"
if [[ "$SKIP_MONITORING" == "false" ]]; then
    echo "4. Import Grafana dashboards (IDs: 23428, 23427, 23712)"
fi
echo ""
echo "📚 **Next Steps:**"
echo "• Review logs if any pods are not running"
echo "• Configure SMTP if not done during deployment"
echo "• Import Grafana Cloud dashboards for monitoring"
echo "• Review security settings in Rocket.Chat admin panel"
echo ""
