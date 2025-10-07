#!/usr/bin/env bash
set -euo pipefail

# Imports recommended dashboards from grafana.com into your Grafana instance (Grafana Cloud supported).
# Requirements:
#  - curl, jq
# Env:
#  - GRAFANA_URL (e.g., https://YOUR_STACK.grafana.net)
#  - GRAFANA_API_KEY (Grafana API key with Dashboard:Write scope)
#  - GRAFANA_DATASOURCE (Prometheus data source name or UID in Grafana)

: "${GRAFANA_URL:?GRAFANA_URL is required, e.g. https://YOUR_STACK.grafana.net}"
: "${GRAFANA_API_KEY:?GRAFANA_API_KEY is required}"
: "${GRAFANA_DATASOURCE:?GRAFANA_DATASOURCE is required (Prometheus data source name or UID)}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found" >&2; exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found" >&2; exit 1
fi

DASHBOARD_IDS=(
  23428  # Rocket.Chat metrics
  23427  # Microservice metrics
  23712  # MongoDB Global (v2)
)

download_dashboard() {
  local id="$1"
  local out="$2"
  # Latest revision download endpoint
  curl -sSfL "https://grafana.com/api/dashboards/${id}/revisions/latest/download" -o "${out}"
}

import_dashboard() {
  local file="$1"

  # Construct import payload:
  # - Wrap dashboard JSON
  # - Overwrite existing dashboards with the same UID or title
  # - Map DS_PROMETHEUS input to the provided datasource name/UID
  local payload
  payload="$(jq -n \
    --argjson db "$(cat "${file}")" \
    --arg ds "${GRAFANA_DATASOURCE}" \
    '{
      dashboard: $db,
      overwrite: true,
      inputs: [
        {
          name: "DS_PROMETHEUS",
          type: "datasource",
          pluginId: "prometheus",
          pluginName: "prometheus",
          value: $ds
        }
      ]
    }'
  )"

  curl -sSf -X POST \
    -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "${payload}" \
    "${GRAFANA_URL}/api/dashboards/import" >/dev/null
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

for id in "${DASHBOARD_IDS[@]}"; do
  echo "Fetching dashboard ${id} ..."
  f="${tmpdir}/dashboard-${id}.json"
  download_dashboard "${id}" "${f}"

  # Ensure downloaded JSON has an appropriate structure (basic sanity)
  if ! jq '.title' < "${f}" >/dev/null 2>&1; then
    echo "Downloaded dashboard ${id} is not valid JSON or missing title" >&2
    exit 1
  fi

  echo "Importing dashboard ${id} into ${GRAFANA_URL} ..."
  import_dashboard "${f}"
  echo "Imported dashboard ${id}."
done

echo "All dashboards imported successfully."
