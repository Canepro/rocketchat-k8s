#!/bin/bash
set -e

echo "============================================"
echo "🚀 Rocket.Chat k3s Deployment Script"
echo "============================================"
echo ""

# Step 1: Apply PVs and PVC
echo "📦 Step 1: Creating Persistent Volumes and Claims..."
kubectl apply -f persistent-volumes.yaml
kubectl apply -f mongo-pvc.yaml
echo "✅ PVs and PVC created"
echo ""

# Wait for PVC to bind
echo "⏳ Waiting for PVC to bind..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/mongo-pvc -n rocketchat --timeout=60s || true
kubectl get pv,pvc -n rocketchat
echo ""

# Step 2: Apply Grafana Cloud secret
echo "🔐 Step 2: Creating Grafana Cloud credentials secret..."
kubectl apply -f grafana-cloud-secret.yaml
echo "✅ Grafana Cloud secret created"
echo ""

# Step 3: Apply Prometheus Agent
echo "📊 Step 3: Deploying Prometheus Agent..."
kubectl apply -f prometheus-agent.yaml
echo "✅ Prometheus Agent deployed"
echo ""

# Wait for Prometheus Agent
echo "⏳ Waiting for Prometheus Agent to be ready..."
kubectl wait --for=condition=available deployment/prometheus-agent -n monitoring --timeout=120s || true
kubectl get pods -n monitoring
echo ""

# Step 4: Apply CRDs
echo "📋 Step 4: Installing PodMonitor and ServiceMonitor CRDs..."
kubectl apply -f podmonitor-crd.yaml
kubectl apply -f servicemonitor-crd.yaml
echo "✅ CRDs installed"
kubectl get crd | grep monitoring.coreos.com
echo ""

# Step 5: Install NGINX Ingress Controller
echo "🌐 Step 5: Installing NGINX Ingress Controller..."
if ! kubectl get namespace ingress-nginx &> /dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
    echo "⏳ Waiting for NGINX Ingress Controller..."
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=300s || true
else
    echo "ℹ️  NGINX Ingress Controller already installed"
fi
echo "✅ NGINX Ingress Controller ready"
echo ""

# Step 6: Install cert-manager
echo "🔒 Step 6: Installing cert-manager..."
if ! kubectl get namespace cert-manager &> /dev/null; then
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
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

# Step 7: Apply ClusterIssuer
echo "📜 Step 7: Creating Let's Encrypt ClusterIssuer..."
kubectl apply -f clusterissuer.yaml
sleep 5
kubectl get clusterissuer
echo "✅ ClusterIssuer created"
echo ""

# Step 8: Add Rocket.Chat Helm repo
echo "📦 Step 8: Adding Rocket.Chat Helm repository..."
helm repo add rocketchat https://rocketchat.github.io/helm-charts 2>/dev/null || true
helm repo update
echo "✅ Helm repo ready"
echo ""

# Step 9: Create SMTP secret
echo "📧 Step 9: Creating SMTP secret..."
echo "⚠️  Please enter your Mailgun SMTP password:"
read -s SMTP_PASSWORD
kubectl create secret generic smtp-credentials -n rocketchat \
  --from-literal=password="$SMTP_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✅ SMTP secret created"
echo ""

# Step 10: Deploy Rocket.Chat
echo "🚀 Step 10: Deploying Rocket.Chat..."
helm upgrade --install rocketchat \
  -n rocketchat \
  -f values.yaml \
  rocketchat/rocketchat
echo "✅ Rocket.Chat deployed"
echo ""

# Wait for pods
echo "⏳ Waiting for Rocket.Chat pods to start..."
sleep 10
kubectl get pods -n rocketchat
echo ""

# Step 11: Verification
echo "============================================"
echo "✅ DEPLOYMENT COMPLETE!"
echo "============================================"
echo ""
echo "📊 Verification Commands:"
echo ""
echo "# Check all pods:"
echo "kubectl get pods -n rocketchat"
echo ""
echo "# Check certificate (may take 2-5 minutes):"
echo "kubectl get certificate -n rocketchat"
echo ""
echo "# Check ingress:"
echo "kubectl get ingress -n rocketchat"
echo ""
echo "# View Prometheus Agent logs:"
echo "kubectl logs -n monitoring deployment/prometheus-agent"
echo ""
echo "# Check Grafana Cloud metrics:"
echo "Go to Grafana Cloud → Explore → Query: up{cluster=\"rocketchat-k3s\"}"
echo ""
echo "🌐 Once certificate is ready, access:"
echo "   https://k8.canepro.me"
echo ""

