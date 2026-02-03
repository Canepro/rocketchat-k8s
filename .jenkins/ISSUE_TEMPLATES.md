# Jenkins GitHub Issue Templates

This document describes the **issue/comment templates** used by the scheduled Jenkins jobs in this repo. These templates are generated in:
- `.jenkins/security-validation.Jenkinsfile`
- `.jenkins/version-check.Jenkinsfile`

The goal is consistent, readable GitHub issues that contain **actionable context** from the Jenkins run.

## Security Scan Findings (Issue)

**Title**: `Security: automated scan findings`

**Sections**:
- Summary (risk level, findings counts, job/build/branch/commit/timestamp)
- Tool results (tfsec, checkov, kube-score, trivy summaries)
- Images scanned (from `trivy-images.txt` when available)
- Artifacts (links to JSON outputs in build artifacts)
- Action required

## Security Scan Findings (Comment Update)

When the issue already exists, the job adds a concise update comment that includes:
- Risk level + counts
- Build + commit + timestamp
- Tool results summary
- Artifact link (build artifacts)

## Version Check – Breaking Updates (Issue)

**Title**: `🚨 Breaking: Major version updates available`

**Sections**:
- Summary (risk level, job/build/branch/commit/timestamp)
- Breaking updates table (Component, Current, Latest, Location, Source)
- Artifacts (version report + per-scope JSON files)
- Action required

## Version Check – Breaking Updates (Comment Update)

If the breaking issue already exists, the job adds a comment with:
- Job/build/branch/commit/timestamp
- The breaking updates table

## CI Failure (Issue)

**Title**: `CI Failure: <JOB_NAME>`

**Sections**:
- Job/build/branch/commit/timestamp
- Next steps (open logs, find first error, re-run)

## CI Failure (Comment Update)

When a failure issue already exists, the job adds a short comment with:
- Job/build/branch/commit/timestamp
- Link back to Jenkins build logs

## Best Practices

1. Keep one open issue per category and rely on comments for updates (prevents spam).
2. Treat CRITICAL as action‑required and schedule remediation work.
3. Use the build link to fetch artifacts and confirm counts.
4. Close issues only when the underlying findings are resolved.
5. Avoid pasting secrets into issues; link to artifacts instead.
