# Weekly AKS Maintenance Automation

This runbook defines the weekly maintenance loop for the Rocket.Chat AKS workload cluster.

## Scope

- Cluster: `rg-canepro-aks/aks-canepro`
- Workload repo: `Canepro/rocketchat-k8s`
- AKS workload plane: Rocket.Chat, MongoDB, NATS, Traefik, cert-manager, External Secrets, Prometheus Agent, Promtail, and OTel Collector
- OKE observability/control plane: Grafana, Prometheus, Loki, Tempo, Argo CD, Jenkins

## Schedule

Run once per week during the normal weekday maintenance window. The Codex app automation owns the schedule; this repo owns the deterministic evidence runner and operator guidance.

Default target: Monday around 13:00 Europe/London. That gives the cluster time to start before the existing Jenkins version/security jobs and leaves the Terraform-managed weekday stop runbook as the cost-control backstop.

## Runner

Use:

```bash
python3 scripts/weekly_aks_maintenance.py --execute --shutdown-mode leave-auto
```

For a safe local preview:

```bash
python3 scripts/weekly_aks_maintenance.py
```

The runner writes evidence under:

```text
reports/weekly-aks-maintenance/<timestamp>/
```

Generated weekly evidence is intentionally ignored by Git. Promote only curated durable reports or docs.

## Guardrails

- `--execute` is required before the runner can start or stop AKS.
- Default shutdown mode is `leave-auto`, because Jenkins jobs may still run inside the existing weekday window.
- Use `--shutdown-mode stop-if-started` only when the weekly run should stop AKS immediately after checks.
- The runner uses a temporary kubeconfig. It does not overwrite the operator kubeconfig.
- Do not print or copy secret values. GitHub, Azure, Jenkins, and observability credentials stay in their configured stores.
- Public GitHub changes are allowed on Vincent's personal repositories when the automation has clear evidence: update labels, comment, close handled issues, update PR metadata, and merge green mergeable PRs when the change matches the repository policy and checks are passing.
- Hard gates still require Vincent's explicit current-run approval: secrets, live cluster mutation outside the runner's weekly AKS start, GitOps/Argo CD mutation, Terraform apply, Helm upgrades, Azure cost or billing actions, ingress changes, and RBAC changes.

## Weekly Checks

The Codex automation should do the following:

1. Pull or inspect the latest `main` branch state.
2. Run the maintenance runner with `--execute --shutdown-mode leave-auto`.
3. Query Grafana MCP on the OKE hub:
   - Datasources: `prometheus`, `loki`, `tempo`
   - Dashboards: `rocketchat-metrics`, `microservice-metrics`, `rocketchat-mongodb-single-node`, `aks-maintenance-jobs`
   - Prometheus: check for Rocket.Chat metrics after startup and check maintenance CronJob freshness.
   - Loki: check recent logs from `monitoring` and `rocketchat` namespaces. If `rocketchat` is absent after startup, call that out.
   - Tempo: check whether trace data is visible when a synthetic trace job ran.
4. Inspect GitHub open issues and PRs:
   - Current known issue: `#113` tracks enabling TLS for operator-managed MongoDB.
   - Current known PR pattern: automated version update PRs should be refreshed before deciding merge readiness.
   - Green, mergeable PRs in Vincent's personal repos may be merged when checks are passing, the diff matches the stated automation policy, and no hard gate is crossed.
   - Issues should be linked to live evidence when possible. Public comments, labels, and closures are allowed on Vincent's personal repos when the evidence supports them.
5. Check update candidates:
   - Parse `VERSIONS.md` for `Can upgrade`, `Check latest`, and `Deprecated`.
   - Treat existing Jenkins version-check PRs as the source of truth for prepared code updates.
   - For risky updates, draft the action and evidence instead of applying directly.
6. Draft a dark-first HTML report using the `codex-html-report` skill. Include:
   - Cluster power-state decision and whether AKS was started.
   - Kubernetes health summary.
   - Rocket.Chat HTTP result.
   - OKE Grafana/Prometheus/Loki/Tempo findings.
   - GitHub issue/PR queue and recommended action.
   - Update candidates and risk.
   - Shutdown decision.
   - Evidence paths.

## Stop Conditions

Stop and ask Vincent before:

- reading or moving secret values
- creating or rotating credentials
- applying Terraform
- running Helm upgrades
- forcing an Argo CD sync/prune
- live Kubernetes mutation outside the runner's weekly AKS start/check path
- changing ingress resources or routing policy
- changing RBAC, identities, role assignments, or service-account authority
- disabling auto-shutdown
- changing spend-affecting Azure settings beyond the weekly AKS start

## Current Context

As of 2026-06-14:

- OKE Grafana MCP exposes datasources `prometheus`, `loki`, and `tempo`.
- Grafana dashboards found: `rocketchat-metrics`, `microservice-metrics`, `rocketchat-mongodb-single-node`, and `aks-maintenance-jobs`.
- Current live GitHub queue had one issue, `#113` for MongoDB TLS, and one green mergeable version update PR, `#131`.
- Current Grafana labels did not show `rocketchat` namespace or `rocketchat_*` metrics in the default query window. Recheck after AKS startup before calling it a fault.
