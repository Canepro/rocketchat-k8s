#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  .jenkins/scripts/sync-jenkinsfiles-to-repo.sh /path/to/target-repo [--commit]

What it does:
  - Copies these files into the target repo:
      .jenkins/version-check.Jenkinsfile
      .jenkins/security-validation.Jenkinsfile
  - Normalizes line endings to LF for the copied files.
  - Optionally commits the changes in the target repo (--commit).

Example (WSL):
  wsl bash -lc "./.jenkins/scripts/sync-jenkinsfiles-to-repo.sh /mnt/d/repos/central-observability-hub-stack --commit"
EOF
}

if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 1
fi

TARGET_REPO="$1"
DO_COMMIT="${2:-}"

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${SRC_ROOT}/.jenkins"

if [[ ! -d "$TARGET_REPO" ]]; then
  echo "ERROR: target repo path does not exist: $TARGET_REPO" >&2
  exit 2
fi

if [[ ! -d "$TARGET_REPO/.git" ]]; then
  echo "WARN: $TARGET_REPO does not look like a git repo (.git missing)." >&2
fi

mkdir -p "$TARGET_REPO/.jenkins"

cp -f "$SRC_DIR/version-check.Jenkinsfile" "$TARGET_REPO/.jenkins/version-check.Jenkinsfile"
cp -f "$SRC_DIR/security-validation.Jenkinsfile" "$TARGET_REPO/.jenkins/security-validation.Jenkinsfile"

# Normalize CRLF -> LF for portability (GNU sed expected in Linux/WSL)
sed -i 's/\r$//' \
  "$TARGET_REPO/.jenkins/version-check.Jenkinsfile" \
  "$TARGET_REPO/.jenkins/security-validation.Jenkinsfile" || true

echo "Synced Jenkinsfiles into: $TARGET_REPO/.jenkins/"

if [[ "$DO_COMMIT" == "--commit" ]]; then
  (
    cd "$TARGET_REPO"
    git add .jenkins/version-check.Jenkinsfile .jenkins/security-validation.Jenkinsfile
    git commit -m "chore: add Jenkins version-check and security-validation pipelines"
  )
  echo "Committed changes in target repo."
else
  echo "Not committing (pass --commit to auto-commit)."
fi

