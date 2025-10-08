# Observability

This repository ships Prometheus Agent v3 remote_write to Grafana Cloud and Kubernetes metrics objects (ServiceMonitor/PodMonitor). Below are recommended Grafana dashboards and a helper to import them into Grafana Cloud.

## Prerequisites

- Prometheus Agent v3 is deployed and successfully remote_writing to Grafana Cloud (see `prometheus-agent.yaml`).
- MongoDB exporter is deployed and scraping (see `mongodb-exporter.yaml`).
- ServiceMonitor/PodMonitor resources are applied and match your namespaces/labels.
- You have a Grafana Cloud stack URL and an API key with Dashboard:Write permissions.

## Recommended Grafana Dashboards

- **Rocket.Chat metrics**
  https://grafana.com/grafana/dashboards/23428-rocket-chat-metrics/
- **Microservice metrics**
  https://grafana.com/grafana/dashboards/23427-microservice-metrics/
- **MongoDB Global (v2)**
  https://grafana.com/grafana/dashboards/23712-mongodb-global2/

These dashboards expect a Prometheus data source (typically named "Prometheus"). If your Grafana Cloud Prometheus data source has a different name, note it for the import step below.

## Option A: Import via Grafana UI

1. In Grafana Cloud, go to Dashboards → Import.
2. Paste a dashboard ID (e.g., 23428) and click Load.
3. Select your Prometheus data source.
4. Click Import.
5. Repeat for the remaining IDs: 23427, 23712.

## Option B: Import via API (scripted)

Use the provided script to download and import dashboards automatically.

Environment variables required:
- `GRAFANA_URL` — your Grafana Cloud URL, e.g. `https://YOUR_STACK.grafana.net`
- `GRAFANA_API_KEY` — API key with Dashboard:Write scope
- `GRAFANA_DATASOURCE` — your Prometheus data source name or UID in Grafana (name usually works)

Example:
```bash
export GRAFANA_URL="https://YOUR_STACK.grafana.net"
export GRAFANA_API_KEY="glc_XXXXXXXXXXXXXXXXXXXXXXXX"
export GRAFANA_DATASOURCE="Prometheus"

./scripts/import-grafana-dashboards.sh
```

Notes:
- The script posts the full dashboard JSON to Grafana's `/api/dashboards/import` with inputs mapping `DS_PROMETHEUS` → `GRAFANA_DATASOURCE`.
- If your Grafana requires a datasource UID instead of name, set `GRAFANA_DATASOURCE` to that UID.

## Verifying Metrics

- **Rocket.Chat**: confirm `rocketchat_*` metrics exist in Explore (Prometheus) and via the ServiceMonitor scrape target.
- **MongoDB**: confirm `mongodb_*` metrics from the exporter.
- **Kubernetes**: ensure the Prometheus Agent remote_write is healthy (no WAL backlog, no remote write errors).

## Current Architecture

**What we have now:**
```
Rocket.Chat Pods → Prometheus Agent v3.0.0 → Grafana Cloud (Metrics)
```

**Capabilities:**
- ✅ Metrics from Rocket.Chat, MongoDB, NATS, Kubernetes
- ✅ Real-time dashboards and alerts
- ✅ Low resource usage (256-512Mi RAM)

---

## Future: Full Observability Stack

**Want metrics + logs + traces?** See **[Observability Roadmap](observability-roadmap.md)** for migration to Grafana Alloy.

**What you'll gain:**
- 📊 **Metrics** - Current functionality (already have)
- 📝 **Logs** - Search and analyze application logs
- 🔍 **Traces** - End-to-end request tracking through microservices
- 🔗 **Correlation** - Jump from metric spike → logs → trace in one click

**Timeline:** After Rocket.Chat is stable (2-4 weeks), migrate from Prometheus Agent to Grafana Alloy for unified observability.

---

## Optional: Next Steps

**Now:**
- Add alert rules and SLOs (availability, latency, error rate) for Rocket.Chat and MongoDB
- Commit curated JSON exports of the dashboards (pin versions) if you want to avoid fetching from grafana.com at deploy time
- If running a local Grafana instead of Grafana Cloud, you can use Grafana provisioning via ConfigMaps to load dashboards automatically

**Later (when ready for full observability):**
- Review [Observability Roadmap](observability-roadmap.md)
- Migrate to Grafana Alloy for logs + traces
- Enable OpenTelemetry in Rocket.Chat
- Create unified dashboards
