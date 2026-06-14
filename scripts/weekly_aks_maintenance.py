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

SECRET_PATTERNS = (
    re.compile(r"(?i)(authorization:\s*(?:bearer|basic)\s+)[^\s]+"),
    re.compile(r"(?i)((?:token|password|secret|apikey|api_key)[=:]\s*)[^\s]+"),
    re.compile(r"gh[opsu]_[A-Za-z0-9_]+"),
)


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
    try:
        return json.loads(result["stdout"])
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
    parser.add_argument("--execute", action="store_true", help="Allow live AKS start/stop actions.")
    parser.add_argument(
        "--shutdown-mode",
        choices=("leave-auto", "stop-if-started"),
        default=os.getenv("AKS_MAINTENANCE_SHUTDOWN_MODE", "leave-auto"),
        help="After checks, either leave the normal auto-shutdown in charge or stop if this run started AKS.",
    )
    parser.add_argument("--wait-timeout", type=int, default=int(os.getenv("AKS_MAINTENANCE_WAIT_TIMEOUT", "900")))
    parser.add_argument("--settle-seconds", type=int, default=int(os.getenv("AKS_MAINTENANCE_SETTLE_SECONDS", "90")))
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

                observability_script = ROOT / "ops" / "scripts" / "verify-observability.sh"
                if observability_script.exists():
                    obs = run(["bash", str(observability_script)], env=env, timeout=300)
                    report["commands"]["ops_verify_observability"] = obs
                    report["kubernetes"]["observability_script_exit_code"] = obs["exit_code"]
    elif report["aks"].get("power_state_after"):
        report["kubernetes"]["reachable"] = False
        report["kubernetes"]["skipped_reason"] = "AKS is not running or required tools are unavailable."

    if report["tools"]["curl"]:
        url = args.rocketchat_url.rstrip("/") + "/api/info"
        http = run(["curl", "-fsS", "--max-time", "20", url], timeout=30)
        report["commands"]["curl_rocketchat_api_info"] = http
        report["http"]["status"] = "ok" if http["exit_code"] == 0 else "failed"
        report["http"]["url"] = url
    else:
        report["http"]["status"] = "skipped"
        report["http"]["reason"] = "curl is not available"

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
