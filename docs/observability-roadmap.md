# Observability Evolution Roadmap

This document outlines the path from basic metrics monitoring to full observability (metrics + logs + traces) using Grafana Alloy.

## Current State (Phase 1) ✅

**Architecture:**
```
Rocket.Chat Pods → Prometheus Agent v3.0.0 → Grafana Cloud (Metrics only)
```

**What we have:**
- ✅ Metrics collection from Rocket.Chat (ports 9100, 9458)
- ✅ MongoDB metrics via built-in Bitnami exporter
- ✅ NATS metrics via exporter
- ✅ Kubernetes cluster metrics
- ✅ Prometheus Agent forwarding to Grafana Cloud
- ✅ Dashboards and alerts in Grafana Cloud

**Configuration files:**
- `prometheus-agent.yaml` - Prometheus Agent v3.0.0 deployment
- `grafana-cloud-secret.yaml` - Authentication credentials
- `podmonitor-crd.yaml` - CRDs for metrics discovery

---

## Future State (Phase 2 & 3) 🚀

**Target Architecture:**
```
Rocket.Chat Pods
├─ Metrics (:9100, :9458)
├─ Logs (stdout/stderr)
└─ Traces (OpenTelemetry)
       ↓
Grafana Alloy (unified collector)
       ↓
Grafana Cloud
├─ Prometheus (metrics)
├─ Loki (logs)
└─ Tempo (traces)
```

---

## Phase 2: Add Logs Collection

**Timeline:** After Rocket.Chat is stable (1-2 weeks minimum)

### Prerequisites
- [ ] Rocket.Chat running smoothly
- [ ] Baseline metrics established
- [ ] Team familiar with Grafana Cloud dashboards
- [ ] Loki enabled in Grafana Cloud account

### What You'll Gain
- Search application logs instantly
- Debug user issues with log context
- Correlate logs with metric spikes
- Audit trail for security events

### Implementation Steps

#### 1. Install Grafana Alloy

Create `grafana-alloy.yaml`:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: grafana-alloy
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: grafana-alloy
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/proxy
      - services
      - endpoints
      - pods
      - events
    verbs: ["get", "list", "watch"]
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs: ["get", "list", "watch"]
  - nonResourceURLs:
      - /metrics
      - /metrics/cadvisor
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: grafana-alloy
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: grafana-alloy
subjects:
  - kind: ServiceAccount
    name: grafana-alloy
    namespace: monitoring
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-alloy-config
  namespace: monitoring
data:
  config.alloy: |
    // Prometheus metrics collection (same as current setup)
    prometheus.scrape "kubernetes_pods" {
      targets = discovery.kubernetes.pods.targets
      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }

    // Log collection from pods
    loki.source.kubernetes "pods" {
      targets    = discovery.kubernetes.pods.targets
      forward_to = [loki.write.grafana_cloud.receiver]
    }

    // Kubernetes service discovery
    discovery.kubernetes "pods" {
      role = "pod"
    }

    // Remote write to Grafana Cloud (Prometheus)
    prometheus.remote_write "grafana_cloud" {
      endpoint {
        url = "https://prometheus-prod-01-gb-south-0.grafana.net/api/prom/push"
        basic_auth {
          username = env("GRAFANA_CLOUD_USERNAME")
          password = env("GRAFANA_CLOUD_PASSWORD")
        }
      }
    }

    // Remote write to Grafana Cloud (Loki)
    loki.write "grafana_cloud" {
      endpoint {
        url = "https://logs-prod-012.grafana.net/loki/api/v1/push"
        basic_auth {
          username = env("GRAFANA_CLOUD_USERNAME")
          password = env("GRAFANA_CLOUD_PASSWORD")
        }
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: grafana-alloy
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: grafana-alloy
  template:
    metadata:
      labels:
        app: grafana-alloy
    spec:
      serviceAccountName: grafana-alloy
      containers:
      - name: alloy
        image: grafana/alloy:latest
        args:
          - run
          - /etc/alloy/config.alloy
          - --server.http.listen-addr=0.0.0.0:12345
          - --storage.path=/var/lib/alloy/data
        env:
        - name: GRAFANA_CLOUD_USERNAME
          valueFrom:
            secretKeyRef:
              name: grafana-cloud-credentials
              key: username
        - name: GRAFANA_CLOUD_PASSWORD
          valueFrom:
            secretKeyRef:
              name: grafana-cloud-credentials
              key: password
        ports:
        - containerPort: 12345
          name: http-metrics
        volumeMounts:
        - name: config
          mountPath: /etc/alloy
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: grafana-alloy-config
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

#### 2. Update Grafana Cloud Secret

Your existing `grafana-cloud-secret.yaml` already has the credentials needed. No changes required!

#### 3. Migration Strategy

**Option A: Gradual Migration (Recommended)**
```bash
# Deploy Alloy alongside Prometheus Agent
kubectl apply -f grafana-alloy.yaml

# Verify both are collecting metrics
kubectl logs -n monitoring -l app=grafana-alloy
kubectl logs -n monitoring deployment/prometheus-agent

# Once confirmed working for 24-48 hours, remove Prometheus Agent
kubectl delete -f prometheus-agent.yaml
```

**Option B: Direct Replacement**
```bash
# Remove Prometheus Agent
kubectl delete -f prometheus-agent.yaml

# Deploy Alloy
kubectl apply -f grafana-alloy.yaml
```

#### 4. Verify Logs in Grafana Cloud

1. Log in to Grafana Cloud
2. Navigate to **Explore** → Select **Loki** datasource
3. Query: `{namespace="rocketchat"}`
4. You should see logs from Rocket.Chat pods

---

## Phase 3: Add Distributed Tracing

**Timeline:** After logs are working (2-4 weeks after Phase 2)

### Prerequisites
- [ ] Alloy deployed and collecting logs
- [ ] Team comfortable with log queries
- [ ] Tempo enabled in Grafana Cloud account
- [ ] Ready to modify Rocket.Chat configuration

### What You'll Gain
- Trace requests end-to-end (UI → API → DB)
- Identify performance bottlenecks
- Visualize microservices dependencies
- Debug slow requests with full context

### Implementation Steps

#### 1. Enable OpenTelemetry in Rocket.Chat

Update `values.yaml`:
```yaml
extraEnv:
  - name: OVERWRITE_SETTING_SMTP_Host
    value: "smtp.mailgun.org"
  - name: OVERWRITE_SETTING_SMTP_Username
    value: "postmaster@canepro.me"
  
  # Add OpenTelemetry configuration
  - name: OTEL_ENABLED
    value: "true"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://grafana-alloy.monitoring.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "rocketchat"
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_traceidratio"
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "0.1"  # Sample 10% of traces
```

#### 2. Update Alloy Configuration

Add to `grafana-alloy-config`:
```alloy
// OTLP receiver for traces
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  http {
    endpoint = "0.0.0.0:4318"
  }
  output {
    traces  = [otelcol.exporter.otlp.grafana_cloud.input]
  }
}

// Export traces to Grafana Cloud Tempo
otelcol.exporter.otlp "grafana_cloud" {
  client {
    endpoint = "tempo-prod-04-gb-south-0.grafana.net:443"
    auth = otelcol.auth.basic.grafana_cloud.handler
  }
}

otelcol.auth.basic "grafana_cloud" {
  username = env("GRAFANA_CLOUD_USERNAME")
  password = env("GRAFANA_CLOUD_PASSWORD")
}
```

#### 3. Update Alloy Deployment

Add ports to the DaemonSet:
```yaml
ports:
- containerPort: 12345
  name: http-metrics
- containerPort: 4317
  name: otlp-grpc
- containerPort: 4318
  name: otlp-http
```

#### 4. Create Alloy Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana-alloy
  namespace: monitoring
spec:
  selector:
    app: grafana-alloy
  ports:
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
  - name: otlp-http
    port: 4318
    targetPort: 4318
```

#### 5. Redeploy Rocket.Chat

```bash
helm upgrade rocketchat -f values.yaml rocketchat/rocketchat -n rocketchat
```

#### 6. Verify Traces

1. Grafana Cloud → **Explore** → Select **Tempo** datasource
2. Query by service name: `{service.name="rocketchat"}`
3. Click on a trace to see the full request flow

---

## Phase 4: Advanced Observability

### Unified Dashboards

Create dashboards that show:
- **Metrics**: CPU, memory, request rate
- **Logs**: Related error messages
- **Traces**: Slow requests breakdown

Click from one to another for correlated troubleshooting.

### Example Use Cases

**Scenario 1: User reports slow message sending**
1. Check metrics: API response time spike at 2:15 PM
2. View logs: Database connection pool exhausted
3. View trace: MongoDB query took 3 seconds (normally 50ms)
4. **Root cause**: Missing database index

**Scenario 2: Pod keeps restarting**
1. Check metrics: Memory usage climbing
2. View logs: "OutOfMemoryError" in application logs
3. View traces: Memory leak in WebSocket connections
4. **Root cause**: WebSocket cleanup not happening

---

## Resource Requirements

### Current (Prometheus Agent)
- Memory: 256Mi - 512Mi
- CPU: 100m - 250m

### Future (Grafana Alloy)
- Memory: 512Mi - 1Gi
- CPU: 250m - 500m

**Note**: Alloy is more resource-intensive but replaces Prometheus Agent and adds logs + traces.

### Recommended Scaling Plan

For your 7.7 GB RAM server:

**Current allocation:**
- Prometheus Agent: 512Mi
- Rocket.Chat (2 replicas): ~2-3Gi
- MongoDB: ~1-2Gi
- NATS (2 replicas): ~512Mi
- System: ~2Gi

**Future with Alloy:**
- Grafana Alloy: 1Gi (instead of Prometheus 512Mi)
- Everything else: same
- **Total increase: ~500Mi**

This is manageable on your current hardware.

---

## Migration Checklist

### Before Migration
- [ ] Rocket.Chat stable for 2+ weeks
- [ ] Baseline metrics documented
- [ ] Team trained on current dashboards
- [ ] Backup of current configurations
- [ ] Test Grafana Cloud Loki/Tempo access

### During Migration
- [ ] Deploy Alloy in test mode alongside Prometheus
- [ ] Verify metrics parity (Alloy vs Prometheus)
- [ ] Enable log collection
- [ ] Verify logs appear in Grafana Cloud
- [ ] Monitor Alloy resource usage
- [ ] Keep Prometheus running for 48 hours as backup

### After Migration
- [ ] Remove Prometheus Agent
- [ ] Update documentation
- [ ] Create new dashboards with logs
- [ ] Train team on log queries
- [ ] Set up log-based alerts

---

## Grafana Cloud Configuration

### Required Products

**Current:**
- ✅ Prometheus (Metrics)

**Phase 2:**
- ✅ Prometheus (Metrics)
- ➕ Loki (Logs)

**Phase 3:**
- ✅ Prometheus (Metrics)
- ✅ Loki (Logs)
- ➕ Tempo (Traces)

### Getting Endpoints

**Loki Push Endpoint:**
1. Grafana Cloud → Loki → Details
2. Copy "Loki URL" (e.g., `https://logs-prod-012.grafana.net`)

**Tempo Endpoint:**
1. Grafana Cloud → Tempo → Details
2. Copy "Tempo endpoint" (e.g., `tempo-prod-04-gb-south-0.grafana.net:443`)

---

## Troubleshooting

### Alloy Not Starting
```bash
kubectl logs -n monitoring -l app=grafana-alloy
kubectl describe daemonset -n monitoring grafana-alloy
```

### Logs Not Appearing in Grafana Cloud
```bash
# Check Alloy is reading logs
kubectl exec -n monitoring -it <alloy-pod> -- cat /var/log/pods/*/*/*.log

# Verify Loki credentials
kubectl get secret -n monitoring grafana-cloud-credentials -o yaml

# Check Alloy config
kubectl get configmap -n monitoring grafana-alloy-config -o yaml
```

### Traces Not Working
```bash
# Verify Rocket.Chat has OTEL enabled
kubectl logs -n rocketchat -l app.kubernetes.io/name=rocketchat | grep -i otel

# Check Alloy OTLP receiver
kubectl port-forward -n monitoring <alloy-pod> 4317:4317
# Test with: grpcurl -plaintext localhost:4317 list

# Verify service exists
kubectl get svc -n monitoring grafana-alloy
```

---

## Cost Considerations

**Grafana Cloud Free Tier (as of 2024):**
- Metrics: 10k series
- Logs: 50 GB/month
- Traces: 50 GB/month

**Your expected usage:**
- Metrics: ~5k series (well within limit)
- Logs: ~10-20 GB/month (depends on log level)
- Traces: ~5-10 GB/month (with 10% sampling)

**Recommendation:** Start with free tier, monitor usage, upgrade if needed.

---

## Next Steps

1. **NOW:** Deploy Rocket.Chat with Prometheus Agent ✅
2. **Week 1-2:** Monitor, tune, stabilize
3. **Week 3:** Review this document and plan Phase 2
4. **Week 4+:** Implement Grafana Alloy with logs
5. **Month 2+:** Add distributed tracing

---

## Additional Resources

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [OpenTelemetry Rocket.Chat](https://docs.rocket.chat/)
- [Loki Query Language (LogQL)](https://grafana.com/docs/loki/latest/logql/)
- [Tempo Tracing](https://grafana.com/docs/tempo/latest/)
- [Alloy Configuration Examples](https://github.com/grafana/alloy/tree/main/example)

---

**Document Version:** 1.0  
**Last Updated:** October 8, 2025  
**Status:** Phase 1 (Prometheus Agent) - Active Deployment

