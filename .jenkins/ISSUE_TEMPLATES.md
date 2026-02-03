# Jenkins GitHub Issue Templates

This document describes the **issue/comment templates** used by the scheduled Jenkins jobs in this repo. These templates are generated in:
- `.jenkins/security-validation.Jenkinsfile`
- `.jenkins/version-check.Jenkinsfile`

The goal is consistent, readable GitHub issues that contain **actionable context** from the Jenkins run.

## Security Scan Findings (Issue)

**Title**: `Security: Critical vulnerabilities detected (automated)`

**Sections**:
- Security Scan Results (risk level, findings: Critical/High/Medium/Low counts)
- Action Required (short paragraph)
- Scan Artifacts (tfsec, checkov, trivy – links or “See Jenkins build artifacts”)
- Next Steps (numbered: review critical findings, create remediation PRs, update policies)
- Origin: “This issue was automatically created by Jenkins security validation pipeline.”

## Security Scan Findings (Comment Update)

When the issue already exists, the job adds a comment:
- **New security scan results** (heading)
- Build link, Findings (counts), Artifacts link
- “(De-dupe enabled: this comment updates an existing open issue.)”

## Version Check – Breaking Updates (Issue)

**Title**: `Breaking: Major version updates available`

**Sections**:
- Version Update Alert (section)
- Risk Level: BREAKING (major version)
- **Updates Available:** Bullet list of "Component: current → latest"
- **Action Required:** Short paragraph (breaking changes, careful testing)
- **Next Steps:** Numbered 1–4 (review release notes, test in staging, upgrade plan, maintenance window)
- Origin: "This issue was automatically created by Jenkins version check pipeline."

## Version Check – Breaking Updates (Comment Update)

If the breaking issue already exists, the job adds a comment:
- **New breaking updates detected** (heading)
- Time (UTC), Build link
- **Updates Available:** Same bullet list (Component: current → latest)

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
