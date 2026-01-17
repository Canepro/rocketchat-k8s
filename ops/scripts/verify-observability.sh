#!/bin/bash
# Observability Verification Script for AKS Cluster
# This script verifies that metrics and traces are flowing from AKS to the observability hub

set -e

NAMESPACE="monitoring"
CLUSTER_LABEL="aks-canepro"

echo "=========================================="
echo "Observability Verification - AKS Cluster"
echo "Cluster: $CLUSTER_LABEL"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

# Step 1: Check Prometheus Agent
echo "Step 1: Checking Prometheus Agent..."
echo "-----------------------------------"

PROM_POD=$(kubectl get pods -n $NAMESPACE -l app=prometheus-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROM_POD" ]; then
    PROM_STATUS=$(kubectl get pod -n $NAMESPACE $PROM_POD -o jsonpath='{.status.phase}')
    PROM_READY=$(kubectl get pod -n $NAMESPACE $PROM_POD -o jsonpath='{.status.containerStatuses[0].ready}')
    
    if [ "$PROM_STATUS" == "Running" ] && [ "$PROM_READY" == "true" ]; then
        print_status 0 "Prometheus Agent pod is Running and Ready"
    else
        print_status 1 "Prometheus Agent pod is not healthy (Status: $PROM_STATUS, Ready: $PROM_READY)"
    fi
    
    # Check for remote_write errors in logs
    PROM_ERRORS=$(kubectl logs -n $NAMESPACE $PROM_POD --tail=50 2>/dev/null | grep -i "error\|fail" | grep -i "write\|remote" | wc -l)
    if [ "$PROM_ERRORS" -eq 0 ]; then
        print_status 0 "No remote_write errors in Prometheus Agent logs"
    else
        print_status 1 "Found $PROM_ERRORS remote_write errors in Prometheus Agent logs"
        echo -e "${YELLOW}  Run: kubectl logs -n $NAMESPACE $PROM_POD${NC}"
    fi
else
    print_status 1 "Prometheus Agent pod not found"
fi

echo ""

# Step 2: Check OTel Collector
echo "Step 2: Checking OTel Collector..."
echo "-----------------------------------"

OTEL_POD=$(kubectl get pods -n $NAMESPACE -l app=otel-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$OTEL_POD" ]; then
    OTEL_STATUS=$(kubectl get pod -n $NAMESPACE $OTEL_POD -o jsonpath='{.status.phase}')
    OTEL_READY=$(kubectl get pod -n $NAMESPACE $OTEL_POD -o jsonpath='{.status.containerStatuses[0].ready}')
    
    if [ "$OTEL_STATUS" == "Running" ] && [ "$OTEL_READY" == "true" ]; then
        print_status 0 "OTel Collector pod is Running and Ready"
    else
        print_status 1 "OTel Collector pod is not healthy (Status: $OTEL_STATUS, Ready: $OTEL_READY)"
    fi
    
    # Check for export errors in logs
    OTEL_ERRORS=$(kubectl logs -n $NAMESPACE $OTEL_POD --tail=50 2>/dev/null | grep -i "error\|fail" | grep -i "export\|trace" | wc -l)
    if [ "$OTEL_ERRORS" -eq 0 ]; then
        print_status 0 "No export errors in OTel Collector logs"
    else
        print_status 1 "Found $OTEL_ERRORS export errors in OTel Collector logs"
        echo -e "${YELLOW}  Run: kubectl logs -n $NAMESPACE $OTEL_POD${NC}"
    fi
else
    print_status 1 "OTel Collector pod not found"
fi

echo ""

# Step 3: Check ConfigMaps
echo "Step 3: Checking Configuration..."
echo "-----------------------------------"

# Check Prometheus Agent config
PROM_CONFIG_CLUSTER=$(kubectl get configmap -n $NAMESPACE prometheus-agent-config -o jsonpath='{.data.prometheus\.yml\.tmpl}' 2>/dev/null | grep -o "cluster: $CLUSTER_LABEL" | head -1)
if [ -n "$PROM_CONFIG_CLUSTER" ]; then
    print_status 0 "Prometheus Agent config has correct cluster label: $CLUSTER_LABEL"
else
    print_status 1 "Prometheus Agent config missing or incorrect cluster label"
fi

# Check OTel Collector config
OTEL_CONFIG_CLUSTER=$(kubectl get configmap -n $NAMESPACE otel-collector-config -o jsonpath='{.data.otel-collector-config\.yaml}' 2>/dev/null | grep -o "value: $CLUSTER_LABEL" | head -1)
if [ -n "$OTEL_CONFIG_CLUSTER" ]; then
    print_status 0 "OTel Collector config has correct cluster attribute: $CLUSTER_LABEL"
else
    print_status 1 "OTel Collector config missing or incorrect cluster attribute"
fi

echo ""

# Step 4: Check Secrets
echo "Step 4: Checking Secrets..."
echo "-----------------------------------"

OBS_SECRET=$(kubectl get secret -n $NAMESPACE observability-credentials -o name 2>/dev/null)
if [ -n "$OBS_SECRET" ]; then
    print_status 0 "observability-credentials secret exists"
else
    print_status 1 "observability-credentials secret not found"
fi

echo ""

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""
echo "For detailed metrics/traces verification in Grafana:"
echo "  - See: ops/manifests/observability-verification.md"
echo ""
echo "Quick PromQL queries to run in Grafana:"
echo "  - Metrics: {cluster=\"$CLUSTER_LABEL\"}"
echo "  - Success rate: rate(prometheus_remote_storage_succeeded_samples_total{cluster=\"$CLUSTER_LABEL\"}[5m])"
echo ""
echo "Quick Tempo search in Grafana:"
echo "  - Tags: cluster=$CLUSTER_LABEL"
echo ""
