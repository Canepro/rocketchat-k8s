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

Generated weekly evidence is intentionally ignored by Git. Promote only curated durable reports or docs. The browser-readable weekly closeout report under `reports/YYYY-MM-DD-weekly-aks-maintenance.html` is a durable artifact and should be committed when it is the authoritative closeout for that run; raw JSON and timestamped evidence directories stay local unless a specific review needs them in Git.

## Guardrails

- `--execute` is required before the runner can start or stop AKS.
- If AKS is stopped but the activity log already shows a start/stop this week, the runner will not start it again by default. For a deliberate PR CI unblock window, rerun with `--execute --force-start-when-stopped --shutdown-mode leave-auto` after confirming the cost window is acceptable.
- Default shutdown mode is `leave-auto`, because Jenkins jobs may still run inside the existing weekday window.
- Use `--shutdown-mode stop-if-started` only when the weekly run should stop AKS immediately after checks.
- The runner uses a temporary kubeconfig. It does not overwrite the operator kubeconfig.
- Jenkins PR checks that require `aks-agent` may remain `Pending` while AKS is stopped. Treat that as expected capacity state, not a failed PR. Start AKS through the weekly runner, verify the AKS static agent, then refresh PR checks before any merge decision.
- Do not print or copy secret values. GitHub, Azure, Jenkins, and observability credentials stay in their configured stores.
- Public GitHub changes are allowed on Vincent's personal repositories when the automation has clear evidence: update labels, comment, close handled issues, update PR metadata, and merge green mergeable PRs when the change matches the repository policy and checks are passing.
- Repo-backed GitOps changes are allowed on Vincent's personal repos when they are the right delivery path and the approved Azure-side or OKE-side reconciler will apply them from Git.
- Terraform apply is allowed when `terraform fmt -check`, `terraform validate`, and a reviewed plan all pass, the plan matches the intended maintenance change, and the run does not print secret values.
- Argo CD refresh and sync actions are allowed for known applications when they reconcile the expected Git revision and health/sync status is checked before and after the action.
- Hard gates still require Vincent's explicit current-run approval: secrets, direct live cluster mutation outside the runner's weekly AKS start, out-of-band GitOps mutation, direct Helm upgrades outside GitOps, Azure cost or billing actions not already represented in a checked Terraform plan, ingress changes, RBAC changes, Argo CD prune/force/delete/rollback actions, and destructive resource deletion.

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
   - Rocket.Chat HTTP: when the runner starts AKS, treat an initial `/api/info` failure as startup lag until the bounded retry window expires. Record final HTTP status code and attempt count.
   - Jenkins: verify the Azure AKS static agent separately from the OKE controller. The static `jenkins-static-agent` deployment runs in AKS namespace `jenkins`; it should have Ready pods before Jenkins jobs that target `aks-agent` are treated as healthy.
   - Jenkins PR checks: if a PR check is `Pending` before AKS starts and targets `aks-agent`, do not classify the PR as blocked. After the runner starts AKS, confirm `jenkins-static-agent` is Ready, then refresh the PR check. If the runner skips start because AKS already had start/stop activity this week, use `--force-start-when-stopped` for the deliberate PR-unblock window instead of leaving the PR stuck on offline CI capacity. Only block or skip the merge if the refreshed check fails, remains pending after the agent is healthy and Jenkins has had time to schedule it, or the diff no longer matches policy.
   - OKE Jenkins controller: verify the controller separately from AKS workload health. Public `/login` should not return a 5xx status, the `jenkins` Argo app should be both `Synced` and `Healthy`, the controller pod should be Ready with service endpoints, and startup logs should not contain plugin dependency failures such as `Failed Loading plugin`, `Update required`, `Failed to load`, or the null `SCM.getKey()` pipeline signature.
   - Jenkins managed jobs: confirm `version-check-rocketchat-k8s` and `security-validation-rocketchat-k8s` render from the managed-jobs configmap with `*/main` and the expected Jenkinsfile paths. Check last-build metadata when Jenkins allows anonymous-safe JSON; otherwise record `auth_required` rather than reading credentials.
4. Inspect GitHub open issues and PRs:
   - Current known issue: `#113` tracks enabling TLS for operator-managed MongoDB.
   - Current known PR pattern: automated version update PRs should be refreshed before deciding merge readiness.
   - For PRs whose only blocker is an `aks-agent` Jenkins check while AKS is stopped, start AKS through the runner and refresh checks after the static agent is Ready. If the normal weekly activity gate suppresses a second start, rerun with `--force-start-when-stopped` for the explicit unblock window. Do not leave a PR open merely because CI capacity was offline before the maintenance window.
   - Green, mergeable PRs in Vincent's personal repos may be merged when checks are passing, the diff matches the stated automation policy, and no hard gate is crossed.
   - Issues should be linked to live evidence when possible. Public comments, labels, and closures are allowed on Vincent's personal repos when the evidence supports them.
5. Check update candidates:
   - Parse `VERSIONS.md` for `Can upgrade`, `Check latest`, and `Deprecated`.
   - Treat existing Jenkins version-check PRs as the source of truth for prepared code updates.
   - Apply safe updates through repo-backed GitOps changes when evidence and checks support them and Azure or OKE will reconcile from Git. Draft risky runtime or hard-gated updates instead of applying them directly.
   - Run Terraform apply only after fmt, validate, and plan evidence is clean and the expected diff is documented in the report.
   - Use Argo CD refresh or sync when reconciliation is stale or required after a Git-backed change, then capture before/after health and sync status.
   - When AKS is stopped, still review managed resource group residual cost. Standard Load Balancer, public IPs, and disks can keep billing even with node compute off.
6. Draft a dark-first HTML report using the `codex-html-report` skill. Include:
   - Cluster power-state decision and whether AKS was started.
   - Kubernetes health summary.
   - Rocket.Chat HTTP result, final status code, and attempt count.
   - OKE Grafana/Prometheus/Loki/Tempo findings.
   - AKS Jenkins static agent deployment and pod readiness.
   - Cross-cluster Jenkins topology: the OKE controller and the Azure AKS static agent are separate proof surfaces. Do not treat controller health as proof that `aks-agent` work can run.
   - OKE Jenkins public HTTP/login status, Argo sync/health, pod readiness, service route evidence, startup-log plugin scan, managed-job source rendering, and last-build status or `auth_required`.
   - GitHub issue/PR queue and recommended action.
   - Update candidates and risk.
   - Terraform and Argo CD actions taken, skipped, or blocked.
   - Shutdown decision.
   - Evidence paths.
   - Selene handoff id or exact delivery blocker.
   - Second-brain note path or exact writeback blocker.
   - Source commit ids for any repo changes made during the run.
7. Send Selene a post-run update after the weekly checks and report are complete:
   - Use the approved Selene handoff or notification lane available to the run.
   - Include report path, evidence directory, cluster power-state decision, actions taken, skipped or gated actions, GitHub issue/PR actions, Terraform and Argo CD actions, OKE observability findings, and any follow-up risk Selene should watch.
   - Record the returned handoff or message id in the report and final response. If delivery fails, record the exact blocker and do not claim Selene received it.
8. Write a searchable second-brain activity note for the completed run:
   - Use the second-brain MCP or CLI write path with actor `automation` or `mira`.
   - Title the note with the run date and `Rocket.Chat AKS weekly maintenance`.
   - Include reusable facts, actions taken, gated actions, report path, evidence paths, Selene handoff id, commit ids or PR ids, and next checks.
   - Do not write raw logs, raw transcripts, secret values, kubeconfig contents, OAuth state, tokens, or private credentials.
   - If second-brain writeback fails, record the blocker in the report and final response.
9. Run a closeout audit before the final user response:
   - Inspect the final runner `evidence.json`; if AKS is online, `aks_jenkins_agent.deployment.healthy` must be present and the static-agent pod readiness and findings must be reported.
   - If AKS is online, verify the live static agent separately with `kubectl --context aks-canepro -n jenkins get deployment jenkins-static-agent -o wide` and `kubectl --context aks-canepro -n jenkins get pods -l app=jenkins-static-agent -o wide`.
   - Validate the HTML report parses and includes the final evidence path, Selene handoff id or blocker, second-brain note path or blocker, source commit ids, shutdown decision, and residual risks.
   - Check `git status --short --branch` for this repo and any repo touched during the run. Commit and push scoped source/docs/report changes when allowed; leave unrelated dirty or older untracked files untouched and name them in the final response.
   - Do not close the run while the report says a handoff or second-brain record is required but the artifact lacks the id/path or explicit blocker.

## Stop Conditions

Stop and ask Vincent before:

- reading or moving secret values
- creating or rotating credentials
- applying Terraform without clean fmt, validate, and plan evidence
- applying Terraform when the plan has unexpected deletes, replacements, cost or billing changes outside the expected diff, ingress changes, RBAC or identity changes, or secret-value handling
- running Helm upgrades directly outside GitOps
- running Argo CD prune, force, delete, rollback, or sync against an unverified app or revision
- making out-of-band GitOps changes that are not represented as repo commits or PRs
- live Kubernetes mutation outside the runner's weekly AKS start/check path
- changing ingress resources or routing policy
- changing RBAC, identities, role assignments, or service-account authority
- disabling auto-shutdown
- changing Azure cost or billing settings outside the checked Terraform plan or weekly AKS start

## Current Context

As of 2026-06-14:

- OKE Grafana MCP exposes datasources `prometheus`, `loki`, and `tempo`.
- Grafana dashboards found: `rocketchat-metrics`, `microservice-metrics`, `rocketchat-mongodb-single-node`, and `aks-maintenance-jobs`.
- Current live GitHub queue had one issue, `#113` for MongoDB TLS, and one green mergeable version update PR, `#131`.
- Current Grafana labels did not show `rocketchat` namespace or `rocketchat_*` metrics in the default query window. Recheck after AKS startup before calling it a fault.
