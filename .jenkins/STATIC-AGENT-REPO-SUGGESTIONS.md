# Jenkins Setup Suggestions for Static-Agent Repo

This document gives concrete suggestions so the **static-agent repo**’s Jenkins setup matches rocketchat-k8s: version-check and security jobs, shared patterns, and README content. Use it when implementing or refactoring Jenkinsfiles in the static-agent repo (or when aligning rocketchat-k8s with the same rules).

**Agent labels:** Align with the migration plan. If the static-agent repo uses the same OKE controller + AKS static agent, use `aks-agent` for pipelines that run on the static agent; keep `version-checker`, `security`, `helm` only if you still use OKE dynamic pods for those. For rocketchat-k8s, AKS-bound jobs use `agent { label 'aks-agent' }`; the static-agent repo should match (e.g. `aks-agent` for version-check and security if they run on the static agent).

---

## 1. Version-check job

### 1.1 yq

- **Install mikefarah/yq** (binary), not `apk yq` (different tool).
- **Verify download** with release checksums (e.g. SHA256 from GitHub releases).
- Example pattern:
  - Download `yq` from https://github.com/mikefarah/yq/releases (pin to a version tag, e.g. `v4.35.1`).
  - Download the checksum file, verify, then install (e.g. `mv` to `$WORKDIR/bin/yq` or `/usr/local/bin/yq`).

### 1.2 Paths and WORKDIR

- **Use a fixed WORKDIR** (e.g. `WORKDIR="${WORKSPACE:-.}"` or explicit `WORKDIR=/path`) and **absolute paths** when:
  - Applying manifest updates (any `yq` or file writes).
  - Calling `curl -d @...` so the payload file is always found (e.g. `curl -d @"${WORKDIR}/payload.json"`).
- Ensures behavior is independent of current working directory.

### 1.3 Update loop and failure handling

- **Process substitution** for the update loop: `while read -r ...; do ...; done < <(jq -c ...)`.
- Introduce an **UPDATE_FAILED** flag (e.g. `UPDATE_FAILED=0`; set to `1` on failure in the loop); after the loop, `[ "$UPDATE_FAILED" -ne 0 ] && exit 1` so **failures exit the main shell** (no silent success).

### 1.4 Helm installer

- **Pin the Helm installer** to a version tag (e.g. `v3.14.0` or `v3.15.0`) for reproducibility.
- Use the official get-helm-3 script or download the binary from GitHub releases with a fixed version; avoid “latest” in CI.

### 1.5 ensure_label

- **Single script** `ensure_label.sh` (e.g. created in **Install Tools** stage):
  - Takes arguments such as label name and color (or label name only if color is fixed).
  - Ensures the repo has a GitHub label; creates it if missing (using GitHub API).
- **Source it** in PR/issue blocks and in post-failure blocks: `source "${WORKDIR}/ensure_label.sh"` (or similar, with WORKDIR).
- **Minimal inline fallback** in post (e.g. `post { failure { ... } }`): if the script might be missing (e.g. failed before Install Tools), use a short inline snippet that creates only the critical labels needed for the failure issue, and add a comment like “fallback when ensure_label.sh not available”.

### 1.6 PR/issue logic and comments

- **PR threshold for medium:** Use **≥ 1** so **any** medium update opens a PR (not “N or more”).
- **Remove unreachable else** and add **short comments**:
  - **HIGH → issue** (e.g. “HIGH: open/update breaking-upgrade issue”).
  - **MEDIUM ≥ 1 → PR** (e.g. “MEDIUM: open/update non-breaking PR when at least one medium update”).

### 1.7 PR body content

- PR body must include:
  - **Updates list** (what versions/components are being updated).
  - **Build link** (link to the Jenkins build that produced the PR).
  - **Review checklist** (short list of items for reviewers, e.g. “Check version bumps”, “Confirm no breaking changes”).

---

## 2. Security job

### 2.1 Issues only, no PRs

- **Create issues only** (no PRs). One **canonical issue title**, e.g. `Security: automated scan findings`.
- **De-dupe:** Find an open issue with that title; if found, **add a comment** with the new findings. **Create the issue only if it doesn’t exist.**

### 2.2 JSON bodies and API errors

- **Build comment and issue body JSON with jq** using `--arg` / `--argjson` (no heredocs with raw variable interpolation).
- **Do not hide API failures:**
  - After **comment POST**: `if ! curl ...; then echo "⚠️ WARNING: Failed to add comment to issue"; fi`
  - After **issue POST**: `if ! curl ...; then echo "⚠️ WARNING: Failed to create issue"; fi`
  - No bare `|| true` that swallows failures.

### 2.3 Curl consistency

- **Suppress curl output** the same way for both comment and issue POSTs (e.g. `>/dev/null 2>&1` or `-s -o /dev/null -w "%{http_code}"` and check the code).

### 2.4 Inputs and labels

- **Pass RISK_LEVEL and counts into the shell** (env vars or script args) so the script knows severity and counts.
- **Labels:** Always use `security`, `automated`. **Add `critical` when risk is CRITICAL.**

### 2.5 Single flow and stage name

- **Single flow** for all severities: one “create or update security findings issue” path (find issue by title → add comment if exists, else create issue then optionally add first comment).
- **Rename stage** to something like **Create/Update Security Findings Issue**.

---

## 3. General

### 3.1 WORKDIR and curl payloads

- **Use WORKDIR** for all `curl -d @...` payload paths so payload files are always resolved the same way regardless of `cwd` (e.g. `curl -d @"${WORKDIR}/issue-body.json"`).

### 3.2 Heredocs

- Where heredocs remain, use **closing delimiter at column 0** (no leading spaces), e.g.:
  ```sh
  cat <<'EOF'
  body content
  EOF
  ```

### 3.3 Agent labels

- Align with the migration plan:
  - If the repo uses the **static AKS agent**, use **`aks-agent`** for version-check and security (and any other AKS-bound pipelines).
  - If it still uses OKE dynamic pods, keep **`version-checker`**, **`security`**, **`helm`** as in the plan. Prefer **`aks-agent`** for AKS-bound jobs so behavior matches rocketchat-k8s.

### 3.4 README

In **.jenkins/README.md** (or equivalent), add a short section that covers:

- **Version-check PR logic:** HIGH → issue; MEDIUM ≥ 1 → PR; yq and WORKDIR requirements; ensure_label script and fallback.
- **Security:** Issues only; one canonical issue title; de-dupe by finding that open issue and adding a comment; create issue only if it doesn’t exist; jq for bodies; no hiding of API failures.

Example subsection:

```markdown
### Version-check pipeline
- **PR logic:** HIGH findings → open/update a single breaking-upgrade issue; MEDIUM (≥1) → open/update a single non-breaking PR.
- **yq:** Uses mikefarah/yq (installed in Install Tools with checksum verification); WORKDIR and absolute paths used for manifest updates and curl payloads.
- **ensure_label:** Central script `ensure_label.sh` created in Install Tools; sourced in PR/issue and post-failure blocks; minimal inline fallback in post if script is missing.

### Security pipeline
- **Issues only** (no PRs). One canonical issue title (e.g. "Security: automated scan findings"); de-dupe by finding that open issue and adding a comment; create the issue only if it doesn’t exist.
- Request/body JSON built with jq (--arg/--argjson); API failures are not hidden (if ! curl ...; then echo "⚠️ WARNING: ..."; fi).
```

---

## 4. Checklist summary

| Area | Suggestion |
|------|------------|
| Version-check | mikefarah/yq + checksum; WORKDIR + absolute paths; process substitution + UPDATE_FAILED; pin Helm version; ensure_label.sh + source + inline fallback; medium PR threshold ≥ 1; PR body: updates list, build link, checklist |
| Security | Issues only; one canonical title; de-dupe by comment; jq for bodies; if ! curl ...; WARNING; same curl suppression; pass RISK_LEVEL/counts; labels security, automated, + critical when CRITICAL; single flow; rename stage |
| General | WORKDIR for curl -d @...; heredoc EOF at column 0; agent labels aligned with plan (aks-agent if static agent) |
| README | Describe version-check PR logic, yq/WORKDIR, ensure_label; describe security issues-only + de-dupe behavior |
