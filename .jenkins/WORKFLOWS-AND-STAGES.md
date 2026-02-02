# rocketchat-k8s Jenkins Workflows and Stages

This document describes the **current** workflows for the version-check job, the security job, and the **repo job** (multibranch pipeline), including all stages and how they are triggered.

---

## 1. Repo job (multibranch pipeline)

**What it is:** A **Multibranch Pipeline** job that runs on every **branch** and every **pull request** for the `rocketchat-k8s` repo. It’s the “repo push / PR validation” pipeline.

**Jenkins setup:**
- **Job type:** Multibranch Pipeline (e.g. job name `rocketchat-k8s`)
- **Script Path:** `.jenkins/terraform-validation.Jenkinsfile` (single script path for the whole multibranch; see note below)
- **Branch source:** GitHub `Canepro/rocketchat-k8s`; discovers branches and PRs
- **Trigger:** GitHub webhook (push/PR) + optional periodic folder scan (e.g. hourly)

**Important:** The multibranch job uses **one** Script Path: `.jenkins/terraform-validation.Jenkinsfile`. So **every** branch and PR currently runs the **Terraform validation** pipeline. There is no separate “helm only” or “terraform + helm” branch in the multibranch; to run helm validation you would either add a second multibranch job with Script Path `.jenkins/helm-validation.Jenkinsfile`, or change the single script path, or use a wrapper Jenkinsfile that runs both.

**Agent:** `aks-agent` (static AKS agent).

### Stages (terraform-validation.Jenkinsfile — repo/PR pipeline)

| # | Stage name        | What it does |
|---|-------------------|--------------|
| 1 | **Setup**         | Install Terraform (unzip + download from HashiCorp); `terraform version` |
| 2 | **Azure Login**   | `az login` with Workload Identity (federated token); `az account set` |
| 3 | **Terraform Format** | `terraform fmt -check -recursive` in `terraform/` |
| 4 | **Terraform Validate** | `terraform init` (Azure backend, OIDC) + `terraform validate` in `terraform/` |
| 5 | **Get Variables** | Copy `terraform.tfvars.example` → `terraform.tfvars` for plan |
| 6 | **Terraform Plan** | `terraform plan -out=tfplan -detailed-exitcode`; fail on exit code 1 |

**Post:** Always archive `tfplan.txt`, clean workspace; success/failure messages.

---

## 2. Version-check job

**What it is:** A **scheduled** pipeline that checks for new versions of Terraform provider, container images, and Helm charts, then creates **one breaking-upgrade issue** and/or **one non-breaking-updates PR** (de-duped).

**Jenkins setup:**
- **Job type:** Usually a **Pipeline** or **Multibranch** with a single branch (e.g. `master`) and Script Path `.jenkins/version-check.Jenkinsfile`
- **Script Path:** `.jenkins/version-check.Jenkinsfile`
- **Schedule:** Weekdays at 5 PM, e.g. `H 17 * * 1-5` (after AKS auto-start at 16:00)
- **Config:** `.jenkins/version-check-job-config.xml` uses this script path

**Agent:** `aks-agent`.

### Stages (version-check.Jenkinsfile)

| # | Stage name                      | What it does |
|---|---------------------------------|--------------|
| 1 | **Install Tools**               | `apk add` curl, jq, git, bash, python3, wget (no apk yq); **mikefarah/yq** v4.35.1 from GitHub with checksums_sha256; Helm get-helm-3 pinned to v3.14.0; single **ensure_label.sh**; verify critical tools |
| 2 | **Check Terraform Versions**    | Read `terraform/main.tf` for azurerm version; Terraform Registry API for latest; write `terraform-versions.json` and `versions.env` |
| 3 | **Check Container Image Versions** | Parse `values.yaml` (yq or grep) for Rocket.Chat image; GitHub/Docker Hub for latest; optional `ops/manifests` images; write `image-updates.json` |
| 4 | **Check Helm Chart Versions**   | Loop ArgoCD app YAMLs; for each chart get current `targetRevision` and latest from chart index; write `chart-updates.json` |
| 5 | **Create Update PRs/Issues**    | Aggregate terraform/images/charts; classify **critical** (major bumps) vs **high/medium**; **critical** → one GitHub **issue** (de-dupe by open issue with same title, else create); **high/medium** (or non-breaking terraform) → one **PR** (de-dupe by existing “Version Updates” PR, update branch and add comment). Source **ensure_label.sh**; issue/comment/PR bodies built with **jq** and `-d @"$WORKDIR/..."`; update loop with process substitution and **UPDATE_FAILED**; `if ! curl ...; then echo "⚠️ WARNING: ..."; fi`. |

**Post:** Always archive `*.json, *.md`. **On failure:** source ensure_label.sh or inline fallback; find or create “CI Failure: &lt;JOB_NAME&gt;” issue; jq-built bodies, `-d @"$WORKDIR/..."`; `if ! curl ...; then echo "⚠️ WARNING: ..."; fi`.

**Current behavior (logic):**
- **HIGH** → contributes to “non-breaking” path (PR).
- **MEDIUM** → contributes to same PR (no separate “medium-only” threshold; PR is created if there are any high or medium or non-breaking terraform).
- **CRITICAL** (major version bumps) → **issue** only; no PR for those items.
- PR threshold for “create PR” is effectively **≥ 1** high or medium (or non-breaking terraform).

---

## 3. Security-validation job

**What it is:** A **scheduled** pipeline that runs tfsec, checkov, kube-score, and trivy, aggregates risk, then either creates a **critical-findings issue** or a **non-critical-findings PR** (current behavior).

**Jenkins setup:**
- **Job type:** Pipeline (or multibranch with one branch) with Script Path `.jenkins/security-validation.Jenkinsfile`
- **Script Path:** `.jenkins/security-validation.Jenkinsfile`
- **Schedule:** Weekdays at 6 PM, e.g. `H 18 * * 1-5`
- **Config:** `.jenkins/security-validation-job-config.xml`

**Agent:** `aks-agent`.

### Stages (security-validation.Jenkinsfile)

| # | Stage name                           | What it does |
|---|--------------------------------------|--------------|
| 1 | **Install Security Tools**           | apk (bash, curl, jq, yq, etc.); install **tfsec** (install script); **checkov** (venv + pip); **trivy** (install script); **kube-score** (apk or binary) |
| 2 | **Terraform Security Scan (tfsec)**  | `tfsec .` in `terraform/`; JSON + default output |
| 3 | **Infrastructure Security Scan (checkov)** | `checkov -d .` in `terraform/`; JSON + CLI output |
| 4 | **Kubernetes Security Scan**         | `kube-score score` on `ops/manifests/*.yaml` (and optional Helm-rendered manifests) |
| 5 | **Container Image Security Scan**    | Parse `values.yaml` for image; `trivy image` for each; JSON + CLI output |
| 6 | **Risk Assessment**                  | Parse tfsec/checkov JSON; count CRITICAL/HIGH/MEDIUM/LOW; compute `risk_level` and `action_required`; write `risk-assessment.json`; **never fail build** (set result SUCCESS) |
| 7 | **Create/Update Security Findings Issue**      | If **CRITICAL** (or critical count ≥ threshold): ensure labels; find open **issue** with title “🚨 Security: Critical vulnerabilities detected (automated)”; if found → **add comment** (heredoc JSON); else → **create issue** (heredoc JSON). Else (non-critical): ensure labels; find open **PR** with title “🔒 Security: Automated remediation (automated)”; if found → add comment; else → create branch, `SECURITY_FIXES.md`, commit, push, **create PR**. |

**Post:** Always archive `*.json, *.md`; print risk summary. **On failure:** ensure_label inline; find/create “CI Failure: &lt;JOB_NAME&gt;” issue; jq-built bodies; `if ! curl ...; then echo "⚠️ WARNING: ..."; fi`.

**Current behavior (logic):**
- **CRITICAL** (or above threshold) → **one canonical issue**; de-dupe by adding a comment to existing open issue with that title.
- **Non-critical** (high/medium/low only) → **PR** with placeholder `SECURITY_FIXES.md`; de-dupe by reusing existing open PR and adding comment.
- So today: **issues for critical**, **PRs for non-critical**. (Suggested change in STATIC-AGENT-REPO-SUGGESTIONS.md: security **issues only**, one canonical “Security: automated scan findings” issue, de-dupe by comment only; no PRs.)

---

## 4. Helm validation (not the multibranch default)

**Script Path:** `.jenkins/helm-validation.Jenkinsfile`. Used when you explicitly create a job (or second multibranch) that points to this file. **Not** the default repo job (the default is terraform-validation only).

**Agent:** `aks-agent`.

### Stages (helm-validation.Jenkinsfile)

| # | Stage name             | What it does |
|---|------------------------|--------------|
| 1 | **Helm Template**      | `helm template rocketchat . -f values.yaml` → `/tmp/manifests.yaml`; optional traefik → `/tmp/traefik-manifests.yaml` |
| 2 | **Kubeconform Validate** | `kubeconform -strict` on both manifest files |
| 3 | **YAML Lint**           | `apk add yamllint`; `yamllint` on `*.yaml` and `ops/manifests/*.yaml` |

**Post:** cleanWs; success/failure messages.

---

## 5. Summary table

| Job                  | Type              | Script path                          | Trigger        | Agent      |
|----------------------|-------------------|---------------------------------------|----------------|------------|
| **Repo (PR/branch)** | Multibranch       | `.jenkins/terraform-validation.Jenkinsfile` | Webhook + scan | `aks-agent` |
| **Version-check**    | Pipeline/scheduled| `.jenkins/version-check.Jenkinsfile`  | Schedule (e.g. 17:00 weekdays) | `aks-agent` |
| **Security**        | Pipeline/scheduled| `.jenkins/security-validation.Jenkinsfile` | Schedule (e.g. 18:00 weekdays) | `aks-agent` |
| **Helm only**       | Optional job      | `.jenkins/helm-validation.Jenkinsfile`    | Manual or separate job | `aks-agent` |

---

## 6. Notes for static-agent repo alignment

- **Version-check:** Uses **mikefarah/yq** (v4.35.1, checksums_sha256); single **ensure_label.sh** (sourced in PR/issue/post; post has minimal inline fallback); PR/issue bodies built with **jq** and `-d @"$WORKDIR/..."`; **WORKDIR** used throughout; update loop with process substitution and **UPDATE_FAILED**; Helm pinned to v3.14.0; `if ! curl ...; then echo "⚠️ WARNING: ..."; fi`. See [STATIC-AGENT-REPO-SUGGESTIONS.md](STATIC-AGENT-REPO-SUGGESTIONS.md) for background.
- **Security:** **Issues only**; one canonical issue "Security: automated scan findings"; jq-built bodies; `if ! curl ...; then echo "⚠️ WARNING: ..."; fi`; no PRs.
- **Repo job:** One multibranch with one script path (terraform only). To run both terraform and helm on every PR you’d add a second pipeline or a wrapper that runs both.
