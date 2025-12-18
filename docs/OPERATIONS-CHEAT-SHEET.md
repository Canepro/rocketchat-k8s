# ⚡ Operations Cheat Sheet

This is a high-density reference for common production operations. For detailed guides, see the [Troubleshooting Guide](troubleshooting.md) and [Observability Quick Reference](OBSERVABILITY-QUICK-REFERENCE.md).

## 🩺 Instant Diagnostics

Run these to see the health of your entire stack at once:

```bash
# Check all pods across both namespaces
kubectl get pods -n rocketchat && kubectl get pods -n monitoring

# Check for any pod restarts or non-running states
kubectl get pods -A | grep -vE "Running|Completed"

# Check TLS certificate status
kubectl get certificate -n rocketchat

# View recent cluster events (errors only)
kubectl get events -A --field-selector type!=Normal --sort-by='.lastTimestamp' | tail -20
```

## 📊 Observability at a Glance

### Critical URLs
* **Grafana:** [https://observability.canepro.me](https://observability.canepro.me)
* **Prometheus:** [https://observability.canepro.me/prometheus](https://observability.canepro.me/prometheus)

### Emergency Queries
* **Error Rate:** `sum(rate(rocketchat_http_requests_total{status=~"5.."}[5m]))`
* **Log Search:** `{namespace="rocketchat"} |= "error"` (Loki)
* **Slow Traces:** `{service.name="rocket-chat" && duration>2s}` (Tempo)

## 🛠️ Recovery Commands

### Restart Services (Safe)
```bash
# Restart App (Zero downtime if replicas > 1)
kubectl rollout restart deployment rocketchat -n rocketchat

# Restart Monitoring Agent
kubectl rollout restart deployment grafana-agent -n monitoring

# Restart MongoDB (Warning: brief disconnection)
kubectl rollout restart statefulset rocketchat-mongodb -n rocketchat
```

### Scale Up/Down
```bash
# Scale main app
kubectl scale deployment rocketchat --replicas=3 -n rocketchat

# Scale microservices (e.g., ddp-streamer)
kubectl scale deployment rocketchat-ddp-streamer --replicas=2 -n rocketchat
```

## 💾 Storage & Resources

```bash
# Check disk usage on node
df -h | grep /mnt

# Check pod resource usage
kubectl top pods -n rocketchat --sort-by=memory

# Check PVC binding status
kubectl get pvc -n rocketchat
```

## 🔐 Credentials Reminder

* **Observability User:** `observability-user`
* **Observability Pass:** `50JjX+diU6YmAZPl`
* **SMTP Config:** Managed in `values.yaml` under `extraEnv`

---
[⬅ Back to Troubleshooting](troubleshooting.md) | [📈 Observability Reference](OBSERVABILITY-QUICK-REFERENCE.md) | [🏠 README](../README.md)

