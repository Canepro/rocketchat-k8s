#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_SCRIPT="${ROOT_DIR}/.jenkins/scripts/send-pipelinehealer-bridge.sh"

if [[ ! -x "${BRIDGE_SCRIPT}" ]]; then
  chmod +x "${BRIDGE_SCRIPT}"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

PORT_FILE="${WORK_DIR}/port"
REQUESTS_FILE="${WORK_DIR}/requests.jsonl"

python3 - <<'PY' "${PORT_FILE}" "${REQUESTS_FILE}" >/dev/null 2>&1 &
import http.server
import json
import socketserver
import sys

port_file, requests_file = sys.argv[1], sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    counter = 0

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        with open(requests_file, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"headers": dict(self.headers), "body": json.loads(body)}) + "\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
        Handler.counter += 1
        if Handler.counter >= 2:
            raise SystemExit(0)

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as fh:
        fh.write(str(httpd.server_address[1]))
    try:
        httpd.serve_forever()
    except SystemExit:
        pass
PY
SERVER_PID=$!

for _ in $(seq 1 50); do
  [[ -s "${PORT_FILE}" ]] && break
  sleep 0.1
done

[[ -s "${PORT_FILE}" ]] || { echo "bridge test server failed to start" >&2; exit 1; }

PORT="$(cat "${PORT_FILE}")"
COMMON_ENV=(
  PH_BRIDGE_URL="http://127.0.0.1:${PORT}/bridge"
  PH_BRIDGE_SECRET="test-secret"
  PH_REPOSITORY="Canepro/rocketchat-k8s"
  PH_JOB_NAME="rocketchat-k8s/test-job"
  PH_JOB_URL="https://jenkins.canepro.me/job/rocketchat-k8s/job/test-job/1/"
  PH_BUILD_NUMBER="1"
  PH_BRANCH="master"
  PH_COMMIT_SHA="0123456789abcdef0123456789abcdef01234567"
  PH_FAILURE_STAGE="terraform-validation"
  PH_FAILURE_SUMMARY="Terraform validation failed"
  PH_RESULT="FAILURE"
)

EXCERPT_FILE="${WORK_DIR}/excerpt.log"
cat >"${EXCERPT_FILE}" <<'EOF'
terraform init
Acquiring state lock. This may take a few moments...
Error: No valid credential sources found
EOF

env "${COMMON_ENV[@]}" PH_LOG_EXCERPT_FILE="${EXCERPT_FILE}" "${BRIDGE_SCRIPT}" >/dev/null

HTML_FILE="${WORK_DIR}/login.html"
cat >"${HTML_FILE}" <<'EOF'
<html><head><title>Login</title></head><body>
Authentication required
</body></html>
EOF

env "${COMMON_ENV[@]}" PH_LOG_EXCERPT_FILE="${HTML_FILE}" "${BRIDGE_SCRIPT}" >/dev/null

wait "${SERVER_PID}"

python3 - <<'PY' "${REQUESTS_FILE}"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    records = [json.loads(line) for line in fh if line.strip()]

assert len(records) == 2, f"expected 2 requests, got {len(records)}"
first = records[0]["body"]
second = records[1]["body"]

assert "No valid credential sources found" in first["failure"]["log_excerpt"]
assert first["metadata"]["bridge_excerpt_present"] == "true"
assert second["failure"]["log_excerpt"] == ""
assert second["metadata"]["bridge_excerpt_present"] == "false"

print("bridge smoke test passed")
PY
