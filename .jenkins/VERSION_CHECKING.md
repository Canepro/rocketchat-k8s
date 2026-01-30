# Automated Version Checking

This document describes how the scheduled Jenkins job (`version-check-…`) detects dependency updates and keeps GitHub “as the dashboard” (issues + PRs), so you don’t have to live in Jenkins logs.

## Overview

The version-check pipeline (`.jenkins/version-check.Jenkinsfile`) does three things:
- **Detect** updates (Terraform provider, Helm charts, Rocket.Chat image)
- **Classify** risk (major = breaking)
- **Report** to GitHub (breaking issue + non-breaking PR), with **de-duplication** so daily runs don’t spam

## What Gets Checked (Current Implementation)

### Terraform
- **AzureRM provider (`azurerm`)**: reads the current version from `terraform/main.tf`, fetches latest from Terraform Registry.

### Rocket.Chat application image
- **Current**: reads `image.repository` + `image.tag` from `values.yaml`
- **Latest**:
  - preferred: Docker Registry API for `registry.rocket.chat`
  - fallback: Rocket.Chat GitHub “latest release” tag

### Helm charts (via ArgoCD Applications)

The pipeline scans `GrafanaLocal/argocd/applications/*.yaml` for Helm sources:
- `repoURL`
- `chart`
- `targetRevision` (current chart version)

Then it fetches `<repoURL>/index.yaml` and picks the latest semver in `.entries[chart][].version`.

## Risk Model (How PR vs Issue is decided)

- **CRITICAL / BREAKING**: major version bump (e.g., `34.x → 39.x`, or `0.x → 1.x`)
  - Creates/updates a single open GitHub issue titled **“🚨 Breaking: Major version updates available”**
- **NON-BREAKING**: minor/patch bumps (e.g., `6.29.0 → 6.30.0`)
  - Creates/updates a single open GitHub PR titled **“⬆️ Version Updates: …”**

### Terraform special case

- Terraform `azurerm` **major** bump is treated as **breaking** (issue).
- Terraform `azurerm` **minor/patch** bump can be included in the non-breaking PR.

## GitHub Output (De-dupe behavior)

### Breaking issue (one open issue, updated by comments)

- **Title**: `🚨 Breaking: Major version updates available`
- **Labels**: `dependencies`, `breaking`, `automated`, `upgrade`
- **Behavior**:
  - if the issue exists: the job **adds a comment** with the latest breaking list (timestamp + build link)
  - if it doesn’t exist: the job creates it

### Non-breaking PR (one open PR, updated by pushing + commenting)

- **Title prefix**: `⬆️ Version Updates:`
- **Labels**: `dependencies`, `automated`, `upgrade`
- **Branch**: `chore/version-updates` (stable; reused across runs)
- **Behavior**:
  - if an open PR exists: the job **pushes updates to the same branch** and comments “PR updated by Jenkins”
  - if it doesn’t exist: the job creates the PR and applies labels

### Failure notifications (so Jenkins failures show up in GitHub)

If the job fails unexpectedly, it creates/updates an issue:
- **Title**: `CI Failure: <JOB_NAME>`
- **Labels**: `ci`, `jenkins`, `failure`, `automated`

## Credentials (GitHub)

The Jenkinsfiles expect a Jenkins credential ID:
- **ID**: `github-token`
- **Type**: **Username with password** (username can be a placeholder; password is the PAT)

In this repo, it is designed to be provisioned automatically via:
- `ops/secrets/externalsecret-jenkins.yaml` (ESO → Kubernetes Secret)
- Jenkins “Kubernetes Credentials Provider” plugin auto-discovers that Secret via annotations/labels

See `.jenkins/GITHUB_CREDENTIALS_SETUP.md` for setup + troubleshooting.

## Operating the system (what future-you does)

- **If you see a breaking issue**: treat it as the “one open ticket for breaking upgrades”. Close it when handled.
- **If you see a version updates PR**: review/merge (or close) when you’re ready. Keeping it open is fine; the job will update it daily.
- **If the cluster is off**: the job won’t run successfully until the cluster is back (scheduled window).

## Pipeline implementation notes

For maintainers: the version-check pipeline uses the following behavior and safeguards:

- **Terraform provider versions**: Provider constraints (e.g. `~> 3.0`) are parsed via a `parseMajorVersion` helper; only the major version is compared for breaking vs non-breaking. Extracted versions are validated (non-empty) before use.
- **Git operations**: All git commands run in the repo workspace via a `gitw()` helper (`git -C "$WORKSPACE" ...`). Push uses `GIT_ASKPASS` so the GitHub token is never stored in `.git/config`; a temporary askpass script is used and cleaned up on exit.
- **GitHub comments**: Comment bodies are built with `printf` and passed to `jq` to avoid shell quoting issues. Optional build-URL lines are constructed in shell before `jq`.
- **Validation**: Invalid or missing issue/PR numbers from GitHub API responses cause the script to skip commenting/updating rather than failing the build.
- **Failure notifications**: On unexpected job failure, the pipeline creates or updates a "CI Failure" GitHub issue so failures are visible in the repo.
