#!/usr/bin/env python3
"""Weekly AKS maintenance runner for the Rocket.Chat deployment.

The script gathers deterministic evidence for the Codex weekly automation. Live
AKS start/stop actions are only allowed when --execute is passed.
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPO = "Canepro/rocketchat-k8s"
DEFAULT_CLUSTER = "aks-canepro"
DEFAULT_RESOURCE_GROUP = "rg-canepro-aks"
DEFAULT_ROCKETCHAT_URL = "https://k8.canepro.me"
DEFAULT_TIMEZONE = "Europe/London"
DEFAULT_OKE_KUBE_CONTEXT = "oke-cluster"
DEFAULT_OKE_JENKINS_URL = "https://jenkins-oke.canepro.me"
DEFAULT_OKE_JENKINS_APP = "jenkins"
DEFAULT_OKE_JENKINS_NAMESPACE = "jenkins"
DEFAULT_OKE_ARGOCD_NAMESPACE = "argocd"
DEFAULT_OKE_MANAGED_JOBS_CONFIGMAP = "jenkins-jenkins-config-managed-jobs"
DEFAULT_AKS_JENKINS_AGENT_NAMESPACE = "jenkins"
DEFAULT_AKS_JENKINS_AGENT_DEPLOYMENT = "jenkins-static-agent"

SECRET_PATTERNS = (
    re.compile(r"(?i)(authorization:\s*(?:bearer|basic)\s+)[^\s]+"),
    re.compile(r"(?i)((?:token|password|secret|apikey|api_key)[=:]\s*)[^\s]+"),
    re.compile(r"gh[opsu]_[A-Za-z0-9_]+"),
)
JSON_CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso_now() -> str:
    return utc_now().isoformat(timespec="seconds").replace("+00:00", "Z")


def redact(text: str) -> str:
    redacted = text
    for pattern in SECRET_PATTERNS:
        redacted = pattern.sub(lambda match: f"{match.group(1)}[redacted]" if match.groups() else "[redacted]", redacted)
    return redacted


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def run(
    args: list[str],
    *,
    env: dict[str, str] | None = None,
    timeout: int = 120,
    cwd: Path = ROOT,
) -> dict[str, Any]:
    started = iso_now()
    try:
        completed = subprocess.run(
            args,
            cwd=str(cwd),
            env=env,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return {
            "command": args,
            "started_at": started,
            "finished_at": iso_now(),
            "exit_code": completed.returncode,
            "stdout": redact(completed.stdout.strip()),
            "stderr": redact(completed.stderr.strip()),
            "timed_out": False,
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "command": args,
            "started_at": started,
            "finished_at": iso_now(),
            "exit_code": 124,
            "stdout": redact((exc.stdout or "").strip() if isinstance(exc.stdout, str) else ""),
            "stderr": redact((exc.stderr or "").strip() if isinstance(exc.stderr, str) else ""),
            "timed_out": True,
        }


def load_json(result: dict[str, Any], default: Any) -> Any:
    if result["exit_code"] != 0 or not result["stdout"]:
        return default
    text = JSON_CONTROL_CHARS.sub("", result["stdout"])
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return default


def local_week_start(timezone_name: str, now: dt.datetime | None = None) -> dt.datetime:
    try:
        from zoneinfo import ZoneInfo

        tz = ZoneInfo(timezone_name)
    except Exception:
        tz = dt.timezone.utc
    local_now = (now or utc_now()).astimezone(tz)
    start = local_now.replace(hour=0, minute=0, second=0, microsecond=0) - dt.timedelta(days=local_now.weekday())
    return start.astimezone(dt.timezone.utc)


def summarize_pods(pods_payload: dict[str, Any]) -> dict[str, Any]:
    items = pods_payload.get("items", []) if isinstance(pods_payload, dict) else []
    bad: list[dict[str, str]] = []
    phases: dict[str, int] = {}
    restarts = 0
    for pod in items:
        meta = pod.get("metadata", {})
        status = pod.get("status", {})
        phase = status.get("phase", "Unknown")
        phases[phase] = phases.get(phase, 0) + 1
        container_statuses = status.get("containerStatuses") or []
        restarts += sum(int(container.get("restartCount", 0) or 0) for container in container_statuses)
        ready = all(container.get("ready") for container in container_statuses) if container_statuses else phase == "Succeeded"
        if phase not in ("Running", "Succeeded") or not ready:
            bad.append(
                {
                    "namespace": meta.get("namespace", ""),
                    "name": meta.get("name", ""),
                    "phase": phase,
                    "reason": status.get("reason", ""),
                }
            )
    return {
        "total": len(items),
        "phases": phases,
        "restart_count_total": restarts,
        "not_ready_or_terminal": bad[:50],
        "truncated": len(bad) > 50,
    }


def summarize_workloads(payload: dict[str, Any]) -> list[dict[str, Any]]:
    items = payload.get("items", []) if isinstance(payload, dict) else []
    summaries: list[dict[str, Any]] = []
    for item in items:
        kind = item.get("kind", "")
        meta = item.get("metadata", {})
        spec = item.get("spec", {})
        status = item.get("status", {})
        desired = spec.get("replicas", status.get("desiredNumberScheduled", 0))
        available = status.get("availableReplicas", status.get("numberAvailable", 0))
        ready = status.get("readyReplicas", status.get("numberReady", available))
        summaries.append(
            {
                "kind": kind,
                "namespace": meta.get("namespace", ""),
                "name": meta.get("name", ""),
                "desired": desired,
                "ready": ready,
                "available": available,
                "healthy": int(ready or 0) >= int(desired or 0),
            }
        )
    return summaries


def summarize_deployment(payload: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, dict) or not payload.get("metadata"):
        return {}
    meta = payload.get("metadata", {})
    spec = payload.get("spec", {})
    status = payload.get("status", {})
    desired = int(spec.get("replicas") or 0)
    ready = int(status.get("readyReplicas") or 0)
    available = int(status.get("availableReplicas") or 0)
    updated = int(status.get("updatedReplicas") or 0)
    return {
        "namespace": meta.get("namespace", ""),
        "name": meta.get("name", ""),
        "desired": desired,
        "ready": ready,
        "available": available,
        "updated": updated,
        "healthy": ready >= desired and available >= desired and updated >= desired,
    }


def deployment_label_selector(payload: dict[str, Any], fallback: str) -> str:
    match_labels = (((payload.get("spec") or {}).get("selector") or {}).get("matchLabels") or {}) if isinstance(payload, dict) else {}
    if not match_labels:
        return fallback
    return ",".join(f"{key}={value}" for key, value in sorted(match_labels.items()))


def summarize_ready_pods(payload: dict[str, Any]) -> dict[str, Any]:
    items = payload.get("items", []) if isinstance(payload, dict) else []
    pods: list[dict[str, Any]] = []
    for pod in items:
        meta = pod.get("metadata", {})
        status = pod.get("status", {})
        container_statuses = status.get("containerStatuses") or []
        ready = bool(container_statuses) and all(container.get("ready") for container in container_statuses)
        pods.append(
            {
                "namespace": meta.get("namespace", ""),
                "name": meta.get("name", ""),
                "phase": status.get("phase", "Unknown"),
                "ready": ready,
                "restart_count": sum(int(container.get("restartCount", 0) or 0) for container in container_statuses),
            }
        )
    return {
        "total": len(pods),
        "ready": sum(1 for pod in pods if pod.get("phase") == "Running" and pod.get("ready")),
        "pods": pods,
    }


def summarize_argo_application(payload: dict[str, Any]) -> dict[str, Any]:
    status = payload.get("status", {}) if isinstance(payload, dict) else {}
    if not status and not payload.get("metadata"):
        return {}
    sync = status.get("sync") or {}
    health = status.get("health") or {}
    operation_state = status.get("operationState") or {}
    history = status.get("history") or []
    latest_history = history[-1] if history else {}
    return {
        "name": (payload.get("metadata") or {}).get("name"),
        "sync_status": sync.get("status"),
        "health_status": health.get("status"),
        "operation_phase": operation_state.get("phase"),
        "operation_message": operation_state.get("message"),
        "revision": sync.get("revision") or latest_history.get("revision"),
        "reconciled_at": status.get("reconciledAt"),
    }


def summarize_jenkins_pod_status(text: str) -> dict[str, Any]:
    pods: list[dict[str, Any]] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        name, phase, created_at, revision, containers = (line.split("\t") + ["", "", "", "", ""])[:5]
        container_states = []
        ready = True
        restart_count = 0
        for raw_container in containers.split(";"):
            if not raw_container:
                continue
            container_name, _, state = raw_container.partition("=")
            ready_text, _, restart_text = state.partition(":")
            container_ready = ready_text == "true"
            ready = ready and container_ready
            try:
                restart_count += int(restart_text or "0")
            except ValueError:
                pass
            container_states.append({"name": container_name, "ready": container_ready})
        pods.append(
            {
                "name": name,
                "phase": phase,
                "created_at": created_at,
                "revision": revision,
                "ready": ready and bool(container_states),
                "restart_count": restart_count,
                "containers": container_states,
            }
        )
    return {
        "total": len(pods),
        "ready": sum(1 for pod in pods if pod.get("ready")),
        "pods": pods,
    }


def summarize_jenkins_managed_jobs(payload: dict[str, Any]) -> dict[str, Any]:
    data = payload.get("data", {}) if isinstance(payload, dict) else {}
    text = "\n".join(str(value) for value in data.values())
    expected = {
        "version-check-rocketchat-k8s": ".jenkins/version-check.Jenkinsfile",
        "security-validation-rocketchat-k8s": ".jenkins/security-validation.Jenkinsfile",
    }
    jobs: dict[str, Any] = {}
    for job, script_path in expected.items():
        start = text.find(job)
        end = text.find("pipelineJob(", start + 1) if start >= 0 else -1
        snippet = text[start : end if end > start else start + 2500] if start >= 0 else ""
        jobs[job] = {
            "present": start >= 0,
            "branch_main": "branch('*/main')" in snippet or 'branch("*/main")' in snippet,
            "script_path_present": script_path in snippet,
            "cron_present": "cron(" in snippet,
        }
    return {
        "configmap_present": bool(data),
        "jobs": jobs,
    }


def summarize_jenkins_logs(text: str) -> dict[str, Any]:
    return {
        "fully_up": "Jenkins is fully up and running" in text,
        "scm_getkey_null": "SCM.getKey()" in text or 'because "scm" is null' in text,
        "failed_plugin_health": sorted(set(re.findall(r"failed plugins: \[([^\]]+)\]", text)))[:10],
        "failed_loading_plugins": sorted(set(re.findall(r"Failed Loading plugin ([^\n\r]+)", text)))[:25],
        "failed_to_load": len(re.findall(r"Failed to load", text)),
        "severe_count": len(re.findall(r"\bSEVERE\b", text)),
        "plugin_wrapper_count": len(re.findall(r"hudson\.PluginWrapper", text)),
        "requires_jenkins": sorted(set(re.findall(r"requires Jenkins ([^\n\r]+)", text)))[:25],
        "update_required": sorted(set(re.findall(r"Update required: ([^\n\r]+)", text)))[:25],
    }


def summarize_jenkins_job_api(job: str, result: dict[str, Any]) -> dict[str, Any]:
    payload = load_json(result, {})
    stdout = result.get("stdout", "")
    stdout_lower = stdout.lower()
    json_parse_ok = bool(payload)
    auth_required = (
        result.get("exit_code") != 0
        and stdout == ""
        and ("403" in result.get("stderr", "") or "401" in result.get("stderr", ""))
    ) or ("<html" in stdout_lower and ("login" in stdout_lower or "sign in" in stdout_lower))
    return {
        "job": job,
        "query_exit_code": result.get("exit_code"),
        "json_parse_ok": json_parse_ok,
        "auth_required": auth_required,
        "result": payload.get("result"),
        "building": payload.get("building"),
        "timestamp": payload.get("timestamp"),
        "duration": payload.get("duration"),
        "url_present": bool(payload.get("url")),
    }


def build_oke_jenkins_findings(oke: dict[str, Any]) -> list[str]:
    findings: list[str] = []
    http_code = str(oke.get("public_login_status_code", "")).strip()
    if http_code and http_code != "200":
        findings.append(f"OKE Jenkins public login returned HTTP {http_code}.")

    app = oke.get("argo_application") or {}
    if oke.get("argo_application_available") is False:
        findings.append("Argo app jenkins check failed.")
    elif app:
        if app.get("sync_status") != "Synced":
            findings.append(f"Argo app jenkins sync status is {app.get('sync_status')}.")
        if app.get("health_status") != "Healthy":
            findings.append(f"Argo app jenkins health status is {app.get('health_status')}.")

    pods = oke.get("pods") or {}
    if pods and pods.get("ready") != pods.get("total"):
        findings.append(f"Jenkins controller pods ready {pods.get('ready')}/{pods.get('total')}.")

    logs = oke.get("startup_log_signatures") or {}
    if logs.get("scm_getkey_null"):
        findings.append("Jenkins logs contain the null SCM.getKey() pipeline failure signature.")
    if logs.get("failed_plugin_health") or logs.get("failed_loading_plugins") or logs.get("update_required"):
        findings.append("Jenkins logs contain failed plugin or dependency update signatures.")

    managed_jobs = oke.get("managed_jobs") or {}
    for job, state in (managed_jobs.get("jobs") or {}).items():
        if not state.get("present"):
            findings.append(f"Managed job {job} is missing from the Jenkins managed-jobs configmap.")
        elif not state.get("branch_main") or not state.get("script_path_present"):
            findings.append(f"Managed job {job} does not render the expected main branch and Jenkinsfile path.")

    for job in oke.get("last_builds", []):
        if job.get("auth_required"):
            continue
        if job.get("query_exit_code") != 0 or not job.get("json_parse_ok"):
            findings.append(f"Managed job {job.get('job')} last-build API check failed.")
        elif job.get("result") not in ("SUCCESS", None) and not job.get("building"):
            findings.append(f"Managed job {job.get('job')} last result is {job.get('result')}.")

    return findings


def build_aks_jenkins_agent_findings(agent: dict[str, Any]) -> list[str]:
    findings: list[str] = []
    if agent.get("skipped_reason"):
        findings.append(f"AKS Jenkins static agent check skipped: {agent['skipped_reason']}.")
        return findings

    deployment = agent.get("deployment") or {}
    if not deployment:
        findings.append("AKS Jenkins static agent deployment was not found.")
    elif not deployment.get("healthy"):
        findings.append(
            "AKS Jenkins static agent deployment ready "
            f"{deployment.get('ready')}/{deployment.get('desired')}."
        )

    pods = agent.get("pods") or {}
    if not pods or pods.get("total", 0) == 0:
        findings.append("AKS Jenkins static agent has no matching pods.")
    elif pods.get("ready") != pods.get("total"):
        findings.append(f"AKS Jenkins static agent pods ready {pods.get('ready')}/{pods.get('total')}.")

    for pod in pods.get("pods", []):
        if pod.get("restart_count", 0) > 0:
            findings.append(f"AKS Jenkins static agent pod {pod.get('name')} has {pod.get('restart_count')} restarts.")
    return findings


def http_check_succeeded(result: dict[str, Any]) -> bool:
    status_code = str(result.get("stdout", "")).strip()
    return result.get("exit_code") == 0 and status_code.startswith("2")


def parse_version_candidates() -> list[dict[str, str]]:
    versions = ROOT / "VERSIONS.md"
    if not versions.exists():
        return []
    candidates: list[dict[str, str]] = []
    for line in versions.read_text(encoding="utf-8").splitlines():
        if "|" not in line:
            continue
        lowered = line.lower()
        if "can upgrade" not in lowered and "check latest" not in lowered and "deprecated" not in lowered:
            continue
        cells = [cell.strip(" *`") for cell in line.strip().strip("|").split("|")]
        if len(cells) < 5 or cells[0].lower() == "component":
            continue
        candidates.append(
            {
                "component": cells[0],
                "current": cells[1],
                "latest_recorded": cells[2],
                "status": cells[3],
                "location": cells[4],
            }
        )
    return candidates


def write_summary(report_dir: Path, report: dict[str, Any]) -> Path:
    lines = [
        f"# Weekly AKS maintenance evidence - {report['generated_at']}",
        "",
        f"- Cluster: `{report['config']['resource_group']}/{report['config']['cluster']}`",
        f"- Mode: `{'execute' if report['config']['execute'] else 'dry-run'}`",
        f"- Shutdown mode: `{report['config']['shutdown_mode']}`",
        f"- Started by this run: `{report['aks'].get('started_by_this_run', False)}`",
        f"- Cluster ran this week: `{report['aks'].get('ran_this_week', 'unknown')}`",
        f"- Power state before: `{report['aks'].get('power_state_before', 'unknown')}`",
        f"- Power state after: `{report['aks'].get('power_state_after', 'unknown')}`",
        "",
        "## Health summary",
        "",
        f"- Kubernetes reachable: `{report['kubernetes'].get('reachable', False)}`",
        f"- Rocket.Chat HTTP check: `{report['http'].get('status', 'skipped')}`",
        f"- AKS Jenkins static agent pods ready: `{(report.get('aks_jenkins_agent') or {}).get('pods', {}).get('ready', 'skipped')}/{(report.get('aks_jenkins_agent') or {}).get('pods', {}).get('total', 'skipped')}`",
        f"- OKE Jenkins public login: `{report['oke_jenkins'].get('public_login_status_code', 'skipped')}`",
        f"- OKE Jenkins Argo health: `{(report['oke_jenkins'].get('argo_application') or {}).get('health_status', 'skipped')}`",
        f"- Open PRs: `{len(report['github'].get('pull_requests', []))}`",
        f"- Open issues: `{len(report['github'].get('issues', []))}`",
        f"- Version candidates in VERSIONS.md: `{len(report['updates'].get('version_candidates', []))}`",
        "",
        "## Suggested follow-up",
        "",
    ]
    if report["github"].get("pull_requests"):
        lines.append("- Review open PRs with green checks before any merge decision.")
    if report["github"].get("issues"):
        lines.append("- Review open issues against live cluster evidence from this run.")
    if report["updates"].get("version_candidates"):
        lines.append("- Check candidate updates against release notes before applying changes.")
    if report["oke_jenkins"].get("findings"):
        lines.extend(f"- OKE Jenkins: {finding}" for finding in report["oke_jenkins"]["findings"])
    if (report.get("aks_jenkins_agent") or {}).get("findings"):
        lines.extend(f"- AKS Jenkins static agent: {finding}" for finding in report["aks_jenkins_agent"]["findings"])
    if not lines[-1].startswith("- "):
        lines.append("- No deterministic follow-up was produced by the runner.")

    summary_path = report_dir / "summary.md"
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summary_path


def write_html_index(report_dir: Path, report: dict[str, Any]) -> Path:
    status = "Partial" if report.get("errors") else "Ready for review"
    rows = []
    for key, value in (
        ("Generated", report["generated_at"]),
        ("Cluster", f"{report['config']['resource_group']}/{report['config']['cluster']}"),
        ("Mode", "execute" if report["config"]["execute"] else "dry-run"),
        ("Ran this week", str(report["aks"].get("ran_this_week", "unknown"))),
        ("Power before", str(report["aks"].get("power_state_before", "unknown"))),
        ("Power after", str(report["aks"].get("power_state_after", "unknown"))),
        ("Kubernetes reachable", str(report["kubernetes"].get("reachable", False))),
        ("Rocket.Chat HTTP", str(report["http"].get("status", "skipped"))),
        (
            "AKS Jenkins static agent",
            f"{(report.get('aks_jenkins_agent') or {}).get('pods', {}).get('ready', 'skipped')}/"
            f"{(report.get('aks_jenkins_agent') or {}).get('pods', {}).get('total', 'skipped')} pods ready",
        ),
        ("AKS Jenkins static agent findings", str(len((report.get("aks_jenkins_agent") or {}).get("findings", [])))),
        ("OKE Jenkins public login", str(report["oke_jenkins"].get("public_login_status_code", "skipped"))),
        ("OKE Jenkins Argo health", str((report["oke_jenkins"].get("argo_application") or {}).get("health_status", "skipped"))),
        ("OKE Jenkins findings", str(len(report["oke_jenkins"].get("findings", [])))),
        ("Open issues", str(len(report["github"].get("issues", [])))),
        ("Open PRs", str(len(report["github"].get("pull_requests", [])))),
    ):
        rows.append(f"<tr><th>{html.escape(key)}</th><td>{html.escape(value)}</td></tr>")

    commands = []
    for name, result in report.get("commands", {}).items():
        command = " ".join(result.get("command", []))
        commands.append(
            "<details><summary>"
            + html.escape(name)
            + "</summary><pre>"
            + html.escape(f"$ {command}\nexit={result.get('exit_code')}\n\n{result.get('stdout', '')}\n{result.get('stderr', '')}".strip())
            + "</pre></details>"
        )

    path = report_dir / "index.html"
    path.write_text(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Weekly AKS maintenance evidence</title>
  <style>
    :root {{ color-scheme: dark; --bg:#0b0d11; --panel:#151922; --panel2:#202532; --line:#343b4d; --text:#f2efe8; --muted:#aeb6c4; --accent:#d6aa5c; }}
    body {{ margin:0; background:var(--bg); color:var(--text); font-family:ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; line-height:1.55; }}
    main {{ width:min(1040px,100% - 32px); margin:0 auto; padding:32px 0 64px; }}
    header, section {{ border:1px solid var(--line); border-radius:14px; background:var(--panel); padding:24px; margin:16px 0; }}
    h1 {{ margin:0 0 8px; font-size:2rem; }}
    h2 {{ margin:0 0 12px; font-size:1.2rem; }}
    p, td {{ color:var(--muted); }}
    table {{ width:100%; border-collapse:collapse; overflow:hidden; border-radius:10px; }}
    th, td {{ border-bottom:1px solid var(--line); padding:10px 12px; text-align:left; vertical-align:top; }}
    th {{ width:220px; color:var(--text); background:var(--panel2); }}
    code, pre {{ font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace; }}
    pre {{ overflow:auto; background:#080a0e; border:1px solid var(--line); border-radius:10px; padding:14px; color:#e8ecf2; }}
    summary {{ cursor:pointer; font-weight:700; color:var(--accent); padding:10px 0; }}
    a {{ color:var(--accent); }}
  </style>
</head>
<body>
<main>
  <header>
    <p>Evidence artifact</p>
    <h1>Weekly AKS maintenance evidence</h1>
    <p>Status: {html.escape(status)}. This file is generated by <code>scripts/weekly_aks_maintenance.py</code>; Codex should turn it into the final reader-facing report.</p>
  </header>
  <section>
    <h2>Summary</h2>
    <table>{''.join(rows)}</table>
  </section>
  <section>
    <h2>Command Evidence</h2>
    {''.join(commands) if commands else '<p>No commands captured.</p>'}
  </section>
</main>
</body>
</html>
""",
        encoding="utf-8",
    )
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run weekly AKS maintenance evidence checks.")
    parser.add_argument("--resource-group", default=os.getenv("AKS_RESOURCE_GROUP", DEFAULT_RESOURCE_GROUP))
    parser.add_argument("--cluster", default=os.getenv("AKS_CLUSTER_NAME", DEFAULT_CLUSTER))
    parser.add_argument("--repo", default=os.getenv("GITHUB_REPOSITORY", DEFAULT_REPO))
    parser.add_argument("--rocketchat-url", default=os.getenv("ROCKETCHAT_URL", DEFAULT_ROCKETCHAT_URL))
    parser.add_argument("--timezone", default=os.getenv("AKS_MAINTENANCE_TIMEZONE", DEFAULT_TIMEZONE))
    parser.add_argument("--report-dir", default=os.getenv("AKS_MAINTENANCE_REPORT_DIR", str(ROOT / "reports" / "weekly-aks-maintenance")))
    parser.add_argument("--oke-kube-context", "--oke-context", default=os.getenv("OKE_KUBE_CONTEXT", DEFAULT_OKE_KUBE_CONTEXT))
    parser.add_argument("--oke-jenkins-url", "--jenkins-url", default=os.getenv("OKE_JENKINS_URL", DEFAULT_OKE_JENKINS_URL))
    parser.add_argument("--oke-jenkins-app", default=os.getenv("OKE_JENKINS_APP", DEFAULT_OKE_JENKINS_APP))
    parser.add_argument("--oke-jenkins-namespace", default=os.getenv("OKE_JENKINS_NAMESPACE", DEFAULT_OKE_JENKINS_NAMESPACE))
    parser.add_argument("--oke-argocd-namespace", default=os.getenv("OKE_ARGOCD_NAMESPACE", DEFAULT_OKE_ARGOCD_NAMESPACE))
    parser.add_argument(
        "--aks-jenkins-agent-namespace",
        default=os.getenv("AKS_JENKINS_AGENT_NAMESPACE", DEFAULT_AKS_JENKINS_AGENT_NAMESPACE),
    )
    parser.add_argument(
        "--aks-jenkins-agent-deployment",
        default=os.getenv("AKS_JENKINS_AGENT_DEPLOYMENT", DEFAULT_AKS_JENKINS_AGENT_DEPLOYMENT),
    )
    parser.add_argument(
        "--oke-managed-jobs-configmap",
        default=os.getenv("OKE_MANAGED_JOBS_CONFIGMAP", DEFAULT_OKE_MANAGED_JOBS_CONFIGMAP),
    )
    parser.add_argument("--execute", action="store_true", help="Allow live AKS start/stop actions.")
    parser.add_argument(
        "--shutdown-mode",
        choices=("leave-auto", "stop-if-started"),
        default=os.getenv("AKS_MAINTENANCE_SHUTDOWN_MODE", "leave-auto"),
        help="After checks, either leave the normal auto-shutdown in charge or stop if this run started AKS.",
    )
    parser.add_argument("--wait-timeout", type=int, default=int(os.getenv("AKS_MAINTENANCE_WAIT_TIMEOUT", "900")))
    parser.add_argument("--settle-seconds", type=int, default=int(os.getenv("AKS_MAINTENANCE_SETTLE_SECONDS", "90")))
    parser.add_argument("--http-retry-window", type=int, default=int(os.getenv("AKS_MAINTENANCE_HTTP_RETRY_WINDOW", "300")))
    parser.add_argument("--http-retry-interval", type=int, default=int(os.getenv("AKS_MAINTENANCE_HTTP_RETRY_INTERVAL", "20")))
    args = parser.parse_args()

    stamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    report_dir = Path(args.report_dir) / stamp
    report_dir.mkdir(parents=True, exist_ok=True)

    report: dict[str, Any] = {
        "generated_at": iso_now(),
        "root": str(ROOT),
        "config": {
            "resource_group": args.resource_group,
            "cluster": args.cluster,
            "repo": args.repo,
            "rocketchat_url": args.rocketchat_url,
            "timezone": args.timezone,
            "execute": args.execute,
            "shutdown_mode": args.shutdown_mode,
        },
        "tools": {},
        "commands": {},
        "aks": {},
        "kubernetes": {},
        "aks_jenkins_agent": {},
        "oke_jenkins": {},
        "http": {},
        "github": {},
        "updates": {"version_candidates": parse_version_candidates()},
        "errors": [],
    }

    for tool in ("az", "kubectl", "gh", "curl", "terraform"):
        report["tools"][tool] = command_exists(tool)

    if not report["tools"]["az"]:
        report["errors"].append("Azure CLI is not available; AKS checks skipped.")
    else:
        show = run(
            [
                "az",
                "aks",
                "show",
                "--resource-group",
                args.resource_group,
                "--name",
                args.cluster,
                "--output",
                "json",
            ],
            timeout=120,
        )
        report["commands"]["az_aks_show_initial"] = show
        cluster = load_json(show, {})
        power_before = (cluster.get("powerState") or {}).get("code", "Unknown")
        report["aks"]["power_state_before"] = power_before
        report["aks"]["provisioning_state"] = cluster.get("provisioningState")
        report["aks"]["kubernetes_version"] = cluster.get("kubernetesVersion")
        report["aks"]["current_kubernetes_version"] = cluster.get("currentKubernetesVersion")
        report["aks"]["resource_id_present"] = bool(cluster.get("id"))

        week_start = local_week_start(args.timezone)
        report["aks"]["week_start_utc"] = week_start.isoformat(timespec="seconds").replace("+00:00", "Z")
        ran_this_week = power_before.lower() == "running"
        activity_events: list[dict[str, Any]] = []
        if cluster.get("id"):
            activity = run(
                [
                    "az",
                    "monitor",
                    "activity-log",
                    "list",
                    "--resource-id",
                    cluster["id"],
                    "--start-time",
                    report["aks"]["week_start_utc"],
                    "--output",
                    "json",
                ],
                timeout=180,
            )
            report["commands"]["az_activity_log_this_week"] = activity
            activity_events = load_json(activity, [])
            for event in activity_events:
                operation = event.get("operationName") or {}
                name = " ".join(str(operation.get(key, "")) for key in ("value", "localizedValue")).lower()
                if ("start" in name or "stop" in name) and ("managedclusters" in name or "managed cluster" in name):
                    ran_this_week = True
                    break
        report["aks"]["activity_event_count"] = len(activity_events) if isinstance(activity_events, list) else 0
        report["aks"]["ran_this_week"] = ran_this_week
        report["aks"]["started_by_this_run"] = False

        if not ran_this_week and power_before.lower() == "stopped":
            if args.execute:
                start = run(
                    ["az", "aks", "start", "--resource-group", args.resource_group, "--name", args.cluster, "--output", "json"],
                    timeout=1800,
                )
                report["commands"]["az_aks_start"] = start
                report["aks"]["started_by_this_run"] = start["exit_code"] == 0
                deadline = time.time() + args.wait_timeout
                while time.time() < deadline:
                    current = run(
                        [
                            "az",
                            "aks",
                            "show",
                            "--resource-group",
                            args.resource_group,
                            "--name",
                            args.cluster,
                            "--query",
                            "powerState.code",
                            "--output",
                            "tsv",
                        ],
                        timeout=60,
                    )
                    report["commands"]["az_aks_power_poll"] = current
                    if current["stdout"].strip().lower() == "running":
                        break
                    time.sleep(20)
                if args.settle_seconds > 0:
                    time.sleep(args.settle_seconds)
            else:
                report["aks"]["would_start"] = True

        show_after = run(
            [
                "az",
                "aks",
                "show",
                "--resource-group",
                args.resource_group,
                "--name",
                args.cluster,
                "--query",
                "{powerState:powerState.code,provisioningState:provisioningState,kubernetesVersion:kubernetesVersion,currentKubernetesVersion:currentKubernetesVersion}",
                "--output",
                "json",
            ],
            timeout=120,
        )
        report["commands"]["az_aks_show_after_start_gate"] = show_after
        after_payload = load_json(show_after, {})
        report["aks"]["power_state_after"] = after_payload.get("powerState", "Unknown")
        report["aks"]["provisioning_state_after"] = after_payload.get("provisioningState")

    if report["tools"]["az"] and report["tools"]["kubectl"] and str(report["aks"].get("power_state_after", "")).lower() == "running":
        with tempfile.TemporaryDirectory(prefix="aks-weekly-") as tmpdir:
            kubeconfig = str(Path(tmpdir) / "kubeconfig")
            creds = run(
                [
                    "az",
                    "aks",
                    "get-credentials",
                    "--resource-group",
                    args.resource_group,
                    "--name",
                    args.cluster,
                    "--file",
                    kubeconfig,
                    "--overwrite-existing",
                ],
                timeout=180,
            )
            report["commands"]["az_aks_get_credentials_temp"] = creds
            env = os.environ.copy()
            env["KUBECONFIG"] = kubeconfig
            cluster_info = run(["kubectl", "cluster-info"], env=env, timeout=90)
            report["commands"]["kubectl_cluster_info"] = cluster_info
            report["kubernetes"]["reachable"] = cluster_info["exit_code"] == 0

            if report["kubernetes"]["reachable"]:
                nodes = run(["kubectl", "get", "nodes", "-o", "wide"], env=env, timeout=90)
                pods = run(["kubectl", "get", "pods", "-A", "-o", "json"], env=env, timeout=180)
                workloads = run(
                    ["kubectl", "get", "deploy,statefulset,daemonset", "-A", "-o", "json"],
                    env=env,
                    timeout=180,
                )
                cronjobs = run(["kubectl", "get", "cronjobs", "-n", "monitoring", "-o", "wide"], env=env, timeout=90)
                endpoints = run(["kubectl", "get", "endpointslice", "-n", "rocketchat"], env=env, timeout=90)
                report["commands"]["kubectl_nodes"] = nodes
                report["commands"]["kubectl_pods_json"] = pods
                report["commands"]["kubectl_workloads_json"] = workloads
                report["commands"]["kubectl_monitoring_cronjobs"] = cronjobs
                report["commands"]["kubectl_rocketchat_endpointslices"] = endpoints
                report["kubernetes"]["pods"] = summarize_pods(load_json(pods, {}))
                report["kubernetes"]["workloads"] = summarize_workloads(load_json(workloads, {}))
                agent_deployment = run(
                    [
                        "kubectl",
                        "get",
                        "deployment",
                        args.aks_jenkins_agent_deployment,
                        "-n",
                        args.aks_jenkins_agent_namespace,
                        "-o",
                        "json",
                    ],
                    env=env,
                    timeout=90,
                )
                agent_deployment_payload = load_json(agent_deployment, {})
                agent_selector = deployment_label_selector(
                    agent_deployment_payload,
                    f"app={args.aks_jenkins_agent_deployment}",
                )
                agent_pods = run(
                    [
                        "kubectl",
                        "get",
                        "pods",
                        "-n",
                        args.aks_jenkins_agent_namespace,
                        "-l",
                        agent_selector,
                        "-o",
                        "json",
                    ],
                    env=env,
                    timeout=90,
                )
                report["commands"]["kubectl_aks_jenkins_agent_deployment"] = agent_deployment
                report["commands"]["kubectl_aks_jenkins_agent_pods"] = agent_pods
                report["aks_jenkins_agent"] = {
                    "namespace": args.aks_jenkins_agent_namespace,
                    "deployment_name": args.aks_jenkins_agent_deployment,
                    "pod_selector": agent_selector,
                    "deployment_available": agent_deployment["exit_code"] == 0,
                    "deployment": summarize_deployment(agent_deployment_payload),
                    "pods": summarize_ready_pods(load_json(agent_pods, {})),
                }
                report["aks_jenkins_agent"]["findings"] = build_aks_jenkins_agent_findings(report["aks_jenkins_agent"])

                observability_script = ROOT / "ops" / "scripts" / "verify-observability.sh"
                if observability_script.exists():
                    obs = run(["bash", str(observability_script)], env=env, timeout=300)
                    report["commands"]["ops_verify_observability"] = obs
                    report["kubernetes"]["observability_script_exit_code"] = obs["exit_code"]
    elif report["aks"].get("power_state_after"):
        report["kubernetes"]["reachable"] = False
        report["kubernetes"]["skipped_reason"] = "AKS is not running or required tools are unavailable."
        report["aks_jenkins_agent"] = {
            "namespace": args.aks_jenkins_agent_namespace,
            "deployment_name": args.aks_jenkins_agent_deployment,
            "skipped_reason": report["kubernetes"]["skipped_reason"],
        }
        report["aks_jenkins_agent"]["findings"] = build_aks_jenkins_agent_findings(report["aks_jenkins_agent"])

    if report["tools"]["curl"]:
        url = args.rocketchat_url.rstrip("/") + "/api/info"
        retry_window = max(0, args.http_retry_window if report["aks"].get("started_by_this_run") else 0)
        retry_interval = max(1, args.http_retry_interval)
        deadline = time.time() + retry_window
        attempts: list[dict[str, Any]] = []
        while True:
            http = run(["curl", "-skS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "20", url], timeout=30)
            attempts.append(http)
            report["commands"][f"curl_rocketchat_api_info_attempt_{len(attempts)}"] = http
            if http_check_succeeded(http) or time.time() >= deadline:
                break
            time.sleep(retry_interval)

        final_http = attempts[-1]
        report["http"]["status"] = "ok" if http_check_succeeded(final_http) else "failed"
        report["http"]["status_code"] = final_http.get("stdout", "").strip() or "unknown"
        report["http"]["attempts"] = len(attempts)
        report["http"]["retry_window_seconds"] = retry_window
        report["http"]["url"] = url
    else:
        report["http"]["status"] = "skipped"
        report["http"]["reason"] = "curl is not available"

    report["oke_jenkins"] = {
        "context": args.oke_kube_context,
        "namespace": args.oke_jenkins_namespace,
        "argocd_namespace": args.oke_argocd_namespace,
        "app": args.oke_jenkins_app,
        "url": args.oke_jenkins_url.rstrip("/"),
        "findings": [],
    }
    if report["tools"]["curl"]:
        jenkins_login = run(
            ["curl", "-sk", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "20", args.oke_jenkins_url.rstrip("/") + "/login"],
            timeout=30,
        )
        report["commands"]["curl_oke_jenkins_login"] = jenkins_login
        report["oke_jenkins"]["public_login_status_code"] = jenkins_login.get("stdout", "").strip() or "unknown"
    else:
        report["oke_jenkins"]["public_login_status_code"] = "skipped"

    if report["tools"]["kubectl"] and args.oke_kube_context:
        context_check = run(
            ["kubectl", "--request-timeout=20s", "config", "get-contexts", args.oke_kube_context, "-o", "name"],
            timeout=30,
        )
        report["commands"]["kubectl_oke_context_check"] = context_check
        if context_check["exit_code"] == 0 and context_check.get("stdout", "").strip() == args.oke_kube_context:
            argo_app = run(
                [
                    "kubectl",
                    "--request-timeout=20s",
                    "--context",
                    args.oke_kube_context,
                    "-n",
                    args.oke_argocd_namespace,
                    "get",
                    "application",
                    args.oke_jenkins_app,
                    "-o",
                    "json",
                ],
                timeout=45,
            )
            pod_status = run(
                [
                    "kubectl",
                    "--request-timeout=20s",
                    "--context",
                    args.oke_kube_context,
                    "-n",
                    args.oke_jenkins_namespace,
                    "get",
                    "pod",
                    "jenkins-0",
                    "-o",
                    "jsonpath={.metadata.name}{'\\t'}{.status.phase}{'\\t'}{.metadata.creationTimestamp}{'\\t'}{.metadata.labels.controller-revision-hash}{'\\t'}{range .status.containerStatuses[*]}{.name}={.ready}:{.restartCount};{end}{'\\n'}",
                ],
                timeout=45,
            )
            service_routes = run(
                [
                    "kubectl",
                    "--request-timeout=20s",
                    "--context",
                    args.oke_kube_context,
                    "-n",
                    args.oke_jenkins_namespace,
                    "get",
                    "svc,endpointslice,ingress",
                    "-o",
                    "wide",
                ],
                timeout=45,
            )
            managed_jobs = run(
                [
                    "kubectl",
                    "--request-timeout=20s",
                    "--context",
                    args.oke_kube_context,
                    "-n",
                    args.oke_jenkins_namespace,
                    "get",
                    "configmap",
                    args.oke_managed_jobs_configmap,
                    "-o",
                    "json",
                ],
                timeout=45,
            )
            logs = run(
                [
                    "kubectl",
                    "--request-timeout=20s",
                    "--context",
                    args.oke_kube_context,
                    "-n",
                    args.oke_jenkins_namespace,
                    "logs",
                    "statefulset/jenkins",
                    "-c",
                    "jenkins",
                    "--since=2h",
                    "--tail=500",
                ],
                timeout=60,
            )
            report["commands"]["kubectl_oke_jenkins_argo_app"] = argo_app
            report["commands"]["kubectl_oke_jenkins_pod_status"] = pod_status
            report["commands"]["kubectl_oke_jenkins_service_routes"] = service_routes
            report["commands"]["kubectl_oke_jenkins_managed_jobs"] = managed_jobs
            report["commands"]["kubectl_oke_jenkins_logs"] = logs
            report["oke_jenkins"]["argo_application_available"] = argo_app["exit_code"] == 0
            report["oke_jenkins"]["argo_application"] = summarize_argo_application(load_json(argo_app, {}))
            report["oke_jenkins"]["pods"] = summarize_jenkins_pod_status(pod_status.get("stdout", ""))
            report["oke_jenkins"]["service_routes_available"] = service_routes["exit_code"] == 0
            report["oke_jenkins"]["managed_jobs"] = summarize_jenkins_managed_jobs(load_json(managed_jobs, {}))
            report["oke_jenkins"]["startup_log_signatures"] = summarize_jenkins_logs(logs.get("stdout", ""))
        else:
            report["oke_jenkins"]["skipped_reason"] = f"kubectl context {args.oke_kube_context!r} is unavailable"
    else:
        report["oke_jenkins"]["skipped_reason"] = "kubectl is unavailable or OKE context is not configured"

    if report["tools"]["curl"]:
        last_builds = []
        for job in ("version-check-rocketchat-k8s", "security-validation-rocketchat-k8s"):
            job_result = run(
                [
                    "curl",
                    "-fskS",
                    "-H",
                    "Accept: application/json",
                    "--max-time",
                    "20",
                    f"{args.oke_jenkins_url.rstrip('/')}/job/{job}/lastBuild/api/json?tree=result,building,timestamp,duration,url",
                ],
                timeout=30,
            )
            report["commands"][f"curl_oke_jenkins_{job}_last_build"] = job_result
            last_builds.append(summarize_jenkins_job_api(job, job_result))
        report["oke_jenkins"]["last_builds"] = last_builds
    report["oke_jenkins"]["findings"] = build_oke_jenkins_findings(report["oke_jenkins"])

    if report["tools"]["gh"]:
        issues = run(
            [
                "gh",
                "issue",
                "list",
                "--repo",
                args.repo,
                "--state",
                "open",
                "--limit",
                "50",
                "--json",
                "number,title,labels,updatedAt,url",
            ],
            timeout=120,
        )
        prs = run(
            [
                "gh",
                "pr",
                "list",
                "--repo",
                args.repo,
                "--state",
                "open",
                "--limit",
                "50",
                "--json",
                "number,title,headRefName,baseRefName,isDraft,mergeStateStatus,mergeable,reviewDecision,statusCheckRollup,updatedAt,url",
            ],
            timeout=180,
        )
        report["commands"]["gh_issue_list_open"] = issues
        report["commands"]["gh_pr_list_open"] = prs
        report["github"]["issues"] = load_json(issues, [])
        report["github"]["pull_requests"] = load_json(prs, [])
    else:
        report["github"]["skipped_reason"] = "gh is not available"

    if report["tools"]["terraform"]:
        fmt = run(["terraform", "-chdir=terraform", "fmt", "-check", "-recursive"], timeout=120)
        report["commands"]["terraform_fmt_check"] = fmt

    if (
        args.execute
        and args.shutdown_mode == "stop-if-started"
        and report["aks"].get("started_by_this_run")
        and report["tools"]["az"]
    ):
        stop = run(["az", "aks", "stop", "--resource-group", args.resource_group, "--name", args.cluster], timeout=1800)
        report["commands"]["az_aks_stop"] = stop
        final = run(
            [
                "az",
                "aks",
                "show",
                "--resource-group",
                args.resource_group,
                "--name",
                args.cluster,
                "--query",
                "powerState.code",
                "--output",
                "tsv",
            ],
            timeout=120,
        )
        report["commands"]["az_aks_show_final"] = final
        report["aks"]["power_state_final"] = final.get("stdout", "").strip()
    else:
        report["aks"]["shutdown_decision"] = "left to existing auto-shutdown schedule"

    json_path = report_dir / "evidence.json"
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    summary_path = write_summary(report_dir, report)
    html_path = write_html_index(report_dir, report)

    print(json.dumps({"report_dir": str(report_dir), "json": str(json_path), "summary": str(summary_path), "html": str(html_path)}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
