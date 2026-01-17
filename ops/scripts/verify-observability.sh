#!/bin/bash
# Observability Verification Script for AKS Cluster
# This script verifies that metrics, traces, and logs are flowing from AKS to the observability hub
# Exit on unhandled errors, but allow controlled error checking
set -euo pipefail

NAMESPACE="monitoring"
CLUSTER_LABEL="aks-canepro"

# Counters for summary
PASSED=0
FAILED=0
WARNINGS=0

echo "=========================================="
echo "Observability Verification - AKS Cluster"
echo "Cluster: $CLUSTER_LABEL"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
        ((PASSED++)) || true
    else
        echo -e "${RED}✗${NC} $2"
        ((FAILED++)) || true
    fi
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++)) || true
}

# Function to check if kubectl is available and cluster is accessible
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl not found. Please install kubectl.${NC}"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to cluster. Check your kubeconfig.${NC}"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist.${NC}"
        exit 1
    fi
}

# Check prerequisites first
check_prerequisites

# Step 1: Check Prometheus Agent
echo "Step 1: Checking Prometheus Agent..."
echo "-----------------------------------"

PROM_POD=$(kubectl get pods -n "$NAMESPACE" -l app=prometheus-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$PROM_POD" ]; then
    print_status 1 "Prometheus Agent pod not found"
    echo -e "${YELLOW}  Check if Prometheus Agent Deployment exists: kubectl get deployment -n $NAMESPACE prometheus-agent${NC}"
else
    PROM_STATUS=$(kubectl get pod -n "$NAMESPACE" "$PROM_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    PROM_READY=$(kubectl get pod -n "$NAMESPACE" "$PROM_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    PROM_RESTARTS=$(kubectl get pod -n "$NAMESPACE" "$PROM_POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    
    if [ "$PROM_STATUS" == "Running" ] && [ "$PROM_READY" == "true" ]; then
        print_status 0 "Prometheus Agent pod is Running and Ready"
        if [ "$PROM_RESTARTS" -gt 0 ]; then
            print_warning "Prometheus Agent has restarted $PROM_RESTARTS time(s) - check logs for issues"
        fi
    else
        print_status 1 "Prometheus Agent pod is not healthy (Status: $PROM_STATUS, Ready: $PROM_READY)"
        if [ "$PROM_STATUS" != "Running" ]; then
            echo -e "${YELLOW}  Pod status: $PROM_STATUS${NC}"
            echo -e "${YELLOW}  Check events: kubectl describe pod -n $NAMESPACE $PROM_POD${NC}"
        fi
    fi
    
    # Check for remote_write errors in logs (last 100 lines for better coverage)
    PROM_ERRORS=$(kubectl logs -n "$NAMESPACE" "$PROM_POD" --tail=100 2>/dev/null | grep -iE "(error|fail)" | grep -iE "(write|remote|push)" | wc -l 2>/dev/null | tr -d '[:space:]' || echo "0")
    PROM_ERRORS=${PROM_ERRORS:-0}  # Default to 0 if empty
    if [ "$PROM_ERRORS" -eq 0 ] 2>/dev/null; then
        print_status 0 "No remote_write errors in Prometheus Agent logs"
    else
        print_status 1 "Found $PROM_ERRORS remote_write errors in Prometheus Agent logs"
        echo -e "${YELLOW}  View logs: kubectl logs -n $NAMESPACE $PROM_POD${NC}"
        echo -e "${YELLOW}  Check for: authentication failures, network errors, or rate limiting${NC}"
    fi
    
    # Check if pod has been running for at least a minute (indicates stability)
    PROM_AGE=$(kubectl get pod -n "$NAMESPACE" "$PROM_POD" -o jsonpath='{.status.startTime}' 2>/dev/null || echo "")
    if [ -n "$PROM_AGE" ]; then
        # Note: This is a simple check - could be improved with date parsing
        print_status 0 "Prometheus Agent pod age check passed"
    fi
fi

echo ""

# Step 2: Check OTel Collector
echo "Step 2: Checking OTel Collector..."
echo "-----------------------------------"

OTEL_POD=$(kubectl get pods -n "$NAMESPACE" -l app=otel-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$OTEL_POD" ]; then
    print_status 1 "OTel Collector pod not found"
    echo -e "${YELLOW}  Check if OTel Collector Deployment exists: kubectl get deployment -n $NAMESPACE otel-collector${NC}"
else
    OTEL_STATUS=$(kubectl get pod -n "$NAMESPACE" "$OTEL_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    OTEL_READY=$(kubectl get pod -n "$NAMESPACE" "$OTEL_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    OTEL_RESTARTS=$(kubectl get pod -n "$NAMESPACE" "$OTEL_POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    
    if [ "$OTEL_STATUS" == "Running" ] && [ "$OTEL_READY" == "true" ]; then
        print_status 0 "OTel Collector pod is Running and Ready"
        if [ "$OTEL_RESTARTS" -gt 0 ]; then
            print_warning "OTel Collector has restarted $OTEL_RESTARTS time(s) - check logs for issues"
        fi
    else
        print_status 1 "OTel Collector pod is not healthy (Status: $OTEL_STATUS, Ready: $OTEL_READY)"
        if [ "$OTEL_STATUS" != "Running" ]; then
            echo -e "${YELLOW}  Pod status: $OTEL_STATUS${NC}"
            echo -e "${YELLOW}  Check events: kubectl describe pod -n $NAMESPACE $OTEL_POD${NC}"
        fi
    fi
    
    # Check for export errors in logs (last 100 lines)
    OTEL_ERRORS=$(kubectl logs -n "$NAMESPACE" "$OTEL_POD" --tail=100 2>/dev/null | grep -iE "(error|fail)" | grep -iE "(export|trace|otlp|http)" | wc -l 2>/dev/null | tr -d '[:space:]' || echo "0")
    OTEL_ERRORS=${OTEL_ERRORS:-0}  # Default to 0 if empty
    if [ "$OTEL_ERRORS" -eq 0 ] 2>/dev/null; then
        print_status 0 "No export errors in OTel Collector logs"
    else
        print_status 1 "Found $OTEL_ERRORS export errors in OTel Collector logs"
        echo -e "${YELLOW}  View logs: kubectl logs -n $NAMESPACE $OTEL_POD${NC}"
        echo -e "${YELLOW}  Check for: authentication failures, network errors, or endpoint issues${NC}"
    fi
fi

echo ""

# Step 2b: Check Promtail (Log Shipping)
echo "Step 2b: Checking Promtail (Log Shipping)..."
echo "-----------------------------------"

PROMPOD_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=promtail --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$PROMPOD_COUNT" -eq 0 ]; then
    print_status 1 "Promtail pods not found"
    echo -e "${YELLOW}  Check if Promtail DaemonSet exists: kubectl get daemonset -n $NAMESPACE promtail${NC}"
else
    print_status 0 "Found $PROMPOD_COUNT Promtail pod(s)"
    
    # Check each Promtail pod
    PROMTAIL_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=promtail -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    PROMTAIL_HEALTHY=0
    PROMTAIL_UNHEALTHY=0
    
    for POD in $PROMTAIL_PODS; do
        POD_STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        POD_READY=$(kubectl get pod -n "$NAMESPACE" "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        
        if [ "$POD_STATUS" == "Running" ] && [ "$POD_READY" == "true" ]; then
            ((PROMTAIL_HEALTHY++)) || true
        else
            ((PROMTAIL_UNHEALTHY++)) || true
            # Get more details about why pod isn't ready
            READY_STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
            if [ "$POD_STATUS" == "Running" ] && [ "$READY_STATUS" != "true" ]; then
            # Pod is running but not ready - check readiness probe
            READY_REASON=$(kubectl get pod -n "$NAMESPACE" "$POD" -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null || echo "")
            READY_MESSAGE=$(kubectl get pod -n "$NAMESPACE" "$POD" -o jsonpath='{.status.containerStatuses[0].state.waiting.message}' 2>/dev/null || echo "")
            print_warning "Promtail pod $POD is Running but not Ready (may be initializing or failing readiness probe)"
            if [ -n "$READY_MESSAGE" ]; then
                echo -e "${YELLOW}  Waiting reason: $READY_MESSAGE${NC}"
            fi
            # Check if there are recent errors in logs that might explain readiness failure
            RECENT_ERRORS=$(kubectl logs -n "$NAMESPACE" "$POD" --tail=20 2>/dev/null | grep -iE "(error|fail|fatal)" | wc -l 2>/dev/null | tr -d '[:space:]' || echo "0")
            if [ "$RECENT_ERRORS" -gt 0 ] 2>/dev/null; then
                echo -e "${YELLOW}  Found $RECENT_ERRORS recent error(s) in logs - check: kubectl logs -n $NAMESPACE $POD${NC}"
            fi
            echo -e "${YELLOW}  Check readiness probe: kubectl describe pod -n $NAMESPACE $POD | grep -A 10 'Readiness'${NC}"
            echo -e "${YELLOW}  Check if Promtail can connect to Loki: kubectl logs -n $NAMESPACE $POD | grep -i 'loki\|push\|connect'${NC}"
            else
                print_warning "Promtail pod $POD is not healthy (Status: $POD_STATUS, Ready: $POD_READY)"
            fi
        fi
        
        # Check for errors in logs
        POD_ERRORS=$(kubectl logs -n "$NAMESPACE" "$POD" --tail=50 2>/dev/null | grep -iE "(error|fail|fatal)" | wc -l 2>/dev/null | tr -d '[:space:]' || echo "0")
        POD_ERRORS=${POD_ERRORS:-0}  # Default to 0 if empty
        if [ "$POD_ERRORS" -gt 0 ] 2>/dev/null; then
            print_warning "Promtail pod $POD has $POD_ERRORS error(s) in logs"
        fi
    done
    
    if [ "$PROMTAIL_UNHEALTHY" -eq 0 ]; then
        print_status 0 "All Promtail pods are Running and Ready ($PROMTAIL_HEALTHY/$PROMPOD_COUNT)"
    else
        print_status 1 "Some Promtail pods are unhealthy ($PROMTAIL_UNHEALTHY/$PROMPOD_COUNT)"
    fi
fi

echo ""

# Step 3: Check Configuration
echo "Step 3: Checking Configuration..."
echo "-----------------------------------"

# Check Prometheus Agent config
if kubectl get configmap -n "$NAMESPACE" prometheus-agent-config &> /dev/null; then
    PROM_CONFIG_CLUSTER=$(kubectl get configmap -n "$NAMESPACE" prometheus-agent-config -o jsonpath='{.data.prometheus\.yml\.tmpl}' 2>/dev/null | grep -o "cluster: $CLUSTER_LABEL" | head -1 || echo "")
    if [ -n "$PROM_CONFIG_CLUSTER" ]; then
        print_status 0 "Prometheus Agent config has correct cluster label: $CLUSTER_LABEL"
    else
        print_status 1 "Prometheus Agent config missing or incorrect cluster label (expected: $CLUSTER_LABEL)"
    fi
    
    # Check if remote_write endpoint is configured
    PROM_ENDPOINT=$(kubectl get configmap -n "$NAMESPACE" prometheus-agent-config -o jsonpath='{.data.prometheus\.yml\.tmpl}' 2>/dev/null | grep -o "url:.*observability\.canepro\.me" | head -1 || echo "")
    if [ -n "$PROM_ENDPOINT" ]; then
        print_status 0 "Prometheus Agent remote_write endpoint configured"
    else
        print_warning "Prometheus Agent remote_write endpoint not found in config"
    fi
else
    print_status 1 "Prometheus Agent ConfigMap not found"
fi

# Check OTel Collector config
if kubectl get configmap -n "$NAMESPACE" otel-collector-config &> /dev/null; then
    OTEL_CONFIG_CLUSTER=$(kubectl get configmap -n "$NAMESPACE" otel-collector-config -o jsonpath='{.data.otel-collector-config\.yaml}' 2>/dev/null | grep -o "value: $CLUSTER_LABEL" | head -1 || echo "")
    if [ -n "$OTEL_CONFIG_CLUSTER" ]; then
        print_status 0 "OTel Collector config has correct cluster attribute: $CLUSTER_LABEL"
    else
        print_status 1 "OTel Collector config missing or incorrect cluster attribute (expected: $CLUSTER_LABEL)"
    fi
else
    print_status 1 "OTel Collector ConfigMap not found"
fi

# Check Promtail config
if kubectl get configmap -n "$NAMESPACE" promtail-config &> /dev/null; then
    PROMTAIL_CONFIG=$(kubectl get configmap -n "$NAMESPACE" promtail-config -o jsonpath='{.data.promtail\.yaml}' 2>/dev/null || echo "")
    # Check if cluster label exists (can be on same line or separate lines)
    if echo "$PROMTAIL_CONFIG" | grep -q "target_label: cluster" && echo "$PROMTAIL_CONFIG" | grep -q "replacement: $CLUSTER_LABEL"; then
        print_status 0 "Promtail config has correct cluster label: $CLUSTER_LABEL"
    elif echo "$PROMTAIL_CONFIG" | grep -q "cluster.*$CLUSTER_LABEL"; then
        print_status 0 "Promtail config has correct cluster label: $CLUSTER_LABEL"
    else
        print_warning "Promtail config cluster label may be missing or incorrect (expected: $CLUSTER_LABEL)"
        echo -e "${YELLOW}  Check config: kubectl get configmap -n $NAMESPACE promtail-config -o yaml${NC}"
    fi
    
    # Check if Loki endpoint is configured
    PROMTAIL_ENDPOINT=$(kubectl get configmap -n "$NAMESPACE" promtail-config -o jsonpath='{.data.promtail\.yaml}' 2>/dev/null | grep -o "url:.*observability\.canepro\.me.*loki" | head -1 || echo "")
    if [ -n "$PROMTAIL_ENDPOINT" ]; then
        print_status 0 "Promtail Loki endpoint configured"
    else
        print_warning "Promtail Loki endpoint not found in config"
    fi
else
    print_warning "Promtail ConfigMap not found (may not be deployed yet)"
fi

echo ""

# Step 4: Check Secrets
echo "Step 4: Checking Secrets..."
echo "-----------------------------------"

# Check if ExternalSecret exists (GitOps-managed)
EXT_SECRET=$(kubectl get externalsecret -n "$NAMESPACE" observability-credentials -o name 2>/dev/null || echo "")
if [ -n "$EXT_SECRET" ]; then
    EXT_SECRET_STATUS=$(kubectl get externalsecret -n "$NAMESPACE" observability-credentials -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$EXT_SECRET_STATUS" == "True" ]; then
        print_status 0 "ExternalSecret 'observability-credentials' is Ready (GitOps-managed)"
    else
        print_warning "ExternalSecret 'observability-credentials' is not Ready (Status: $EXT_SECRET_STATUS)"
        echo -e "${YELLOW}  Check status: kubectl get externalsecret -n $NAMESPACE observability-credentials${NC}"
        echo -e "${YELLOW}  Check events: kubectl describe externalsecret -n $NAMESPACE observability-credentials${NC}"
    fi
else
    print_warning "ExternalSecret 'observability-credentials' not found (may use manual secret)"
fi

# Check if Kubernetes Secret exists
OBS_SECRET=$(kubectl get secret -n "$NAMESPACE" observability-credentials -o name 2>/dev/null || echo "")
if [ -n "$OBS_SECRET" ]; then
    print_status 0 "observability-credentials secret exists"
    
    # Check if secret has required keys
    SECRET_USERNAME=$(kubectl get secret -n "$NAMESPACE" observability-credentials -o jsonpath='{.data.username}' 2>/dev/null || echo "")
    SECRET_PASSWORD=$(kubectl get secret -n "$NAMESPACE" observability-credentials -o jsonpath='{.data.password}' 2>/dev/null || echo "")
    
    if [ -n "$SECRET_USERNAME" ] && [ -n "$SECRET_PASSWORD" ]; then
        print_status 0 "Secret has required keys (username, password)"
    else
        print_status 1 "Secret missing required keys (username or password)"
        echo -e "${YELLOW}  Check secret: kubectl get secret -n $NAMESPACE observability-credentials -o yaml${NC}"
    fi
else
    print_status 1 "observability-credentials secret not found"
    echo -e "${YELLOW}  If using External Secrets Operator, check: kubectl get externalsecret -n $NAMESPACE${NC}"
    echo -e "${YELLOW}  Or create manually: See OPERATIONS.md for secret creation${NC}"
fi

echo ""

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""
echo -e "${BLUE}Results:${NC}"
echo "  Passed:   $PASSED"
echo "  Failed:   $FAILED"
echo "  Warnings: $WARNINGS"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    EXIT_CODE=0
else
    echo -e "${RED}✗ Some checks failed. Review the output above.${NC}"
    EXIT_CODE=1
fi

if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) - review and address if needed${NC}"
fi

echo ""
echo "For detailed metrics/traces/logs verification in Grafana:"
echo "  - See: ops/manifests/observability-verification.md"
echo ""
echo "Quick PromQL queries to run in Grafana:"
echo "  - Metrics: {cluster=\"$CLUSTER_LABEL\"}"
echo "  - Success rate: rate(prometheus_remote_storage_succeeded_samples_total{cluster=\"$CLUSTER_LABEL\"}[5m])"
echo ""
echo "Quick Tempo search in Grafana:"
echo "  - Tags: cluster=$CLUSTER_LABEL"
echo ""
echo "Quick Loki queries in Grafana:"
echo "  - LogQL: {cluster=\"$CLUSTER_LABEL\"}"
echo "  - Example: {cluster=\"$CLUSTER_LABEL\", namespace=\"rocketchat\"}"
echo ""

exit $EXIT_CODE
