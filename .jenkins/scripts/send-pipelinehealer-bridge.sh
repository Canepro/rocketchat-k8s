#!/usr/bin/env bash
set -euo pipefail

warn() {
  echo "PipelineHealer bridge: $*" >&2
}

if [[ -z "${PH_BRIDGE_URL:-}" || -z "${PH_BRIDGE_SECRET:-}" ]]; then
  warn "missing PH_BRIDGE_URL or PH_BRIDGE_SECRET; skipping notification"
  exit 0
fi

for cmd in curl openssl python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "required command '$cmd' is unavailable; skipping notification"
    exit 0
  fi
done

TARGET_URL="${PH_BRIDGE_URL%/}"
TARGET_PATH="$(python3 - "$TARGET_URL" <<'PY'
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
if not parsed.scheme or not parsed.netloc:
    raise SystemExit(1)
print(parsed.path or "/")
PY
)" || {
  warn "invalid PH_BRIDGE_URL '${PH_BRIDGE_URL}'"
  exit 0
}

TIMESTAMP="$(date +%s)"
NONCE="${PH_NONCE:-jenkins-${JOB_NAME:-job}-${BUILD_NUMBER:-0}-${TIMESTAMP}}"
BODY_FILE="$(mktemp)"
EXCERPT_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$EXCERPT_FILE"' EXIT

if [[ -n "${PH_LOG_EXCERPT:-}" ]]; then
  printf '%s\n' "${PH_LOG_EXCERPT}" >"$EXCERPT_FILE"
elif [[ -n "${PH_LOG_EXCERPT_FILE:-}" && -f "${PH_LOG_EXCERPT_FILE}" ]]; then
  cat "${PH_LOG_EXCERPT_FILE}" >"$EXCERPT_FILE"
else
  JOB_URL="${PH_JOB_URL:-${BUILD_URL:-}}"
  if [[ -n "$JOB_URL" ]]; then
    curl -fsSL "${JOB_URL%/}/consoleText" >"$EXCERPT_FILE" 2>/dev/null || true
  fi
fi

python3 - "$EXCERPT_FILE" "$BODY_FILE" <<'PY'
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse


def _read_text(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def _clean_commit(value: str) -> str:
    commit = value.strip()
    if len(commit) != 40:
        return ""
    if any(ch not in "0123456789abcdefABCDEF" for ch in commit):
        return ""
    return commit


def _as_int(value: str, default: int = 0) -> int:
    try:
        return int(value.strip())
    except (ValueError, AttributeError):
        return default


excerpt_path, out_path = sys.argv[1], sys.argv[2]
raw_excerpt = _read_text(excerpt_path)
if raw_excerpt:
    raw_excerpt = "\n".join(raw_excerpt.splitlines()[-120:])
if len(raw_excerpt) > 20_000:
    raw_excerpt = raw_excerpt[-20_000:]

job_url = os.getenv("PH_JOB_URL") or os.getenv("BUILD_URL") or ""
job_host = urlparse(job_url).hostname or ""
job_name = os.getenv("PH_JOB_NAME") or os.getenv("JOB_NAME") or "jenkins-job"
summary = (
    os.getenv("PH_FAILURE_SUMMARY")
    or f"Jenkins job {job_name} failed"
)

payload = {
    "schema_version": "1.0",
    "provider": "jenkins",
    "delivery_id": f"jenkins:{job_name}#{os.getenv('PH_BUILD_NUMBER') or os.getenv('BUILD_NUMBER') or '0'}",
    "sent_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "repository": (os.getenv("PH_REPOSITORY") or "Canepro/rocketchat-k8s").lower(),
    "branch": os.getenv("PH_BRANCH") or os.getenv("GIT_BRANCH") or os.getenv("BRANCH_NAME") or "unknown",
    "commit_sha": _clean_commit(os.getenv("PH_COMMIT_SHA") or os.getenv("GIT_COMMIT") or ""),
    "job": {
        "name": job_name,
        "url": job_url,
        "build_number": _as_int(os.getenv("PH_BUILD_NUMBER") or os.getenv("BUILD_NUMBER") or "0"),
        "result": os.getenv("PH_RESULT") or "FAILURE",
        "duration_ms": _as_int(os.getenv("PH_DURATION_MS") or "0"),
    },
    "failure": {
        "stage": os.getenv("PH_FAILURE_STAGE") or "",
        "step": os.getenv("PH_FAILURE_STEP") or "",
        "command": os.getenv("PH_FAILURE_COMMAND") or "",
        "summary": summary,
        "log_excerpt": raw_excerpt,
    },
    "artifacts": [],
    "metadata": {
        "jenkins_instance": job_host,
        "job_name": job_name,
        "build_url": job_url,
    },
}

with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=True)
PY

BODY_SHA="$(openssl dgst -sha256 "$BODY_FILE" | awk '{print $NF}')"
CANONICAL="$(printf 'POST\n%s\n%s\n%s\n%s' "$TARGET_PATH" "$TIMESTAMP" "$NONCE" "$BODY_SHA")"
SIGNATURE="sha256=$(printf '%s' "$CANONICAL" | openssl dgst -sha256 -hmac "$PH_BRIDGE_SECRET" | awk '{print $NF}')"

curl -fsS -X POST "$TARGET_URL" \
  -H "Content-Type: application/json" \
  -H "X-PH-Bridge-Provider: jenkins" \
  -H "X-PH-Bridge-Timestamp: $TIMESTAMP" \
  -H "X-PH-Bridge-Nonce: $NONCE" \
  -H "X-PH-Bridge-Signature: $SIGNATURE" \
  --data-binary @"$BODY_FILE"
