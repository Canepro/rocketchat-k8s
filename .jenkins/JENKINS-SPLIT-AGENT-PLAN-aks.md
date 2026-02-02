# Jenkins Split-Agent Plan (AKS Side)

This document is the **AKS-side** summary of the Jenkins split-agent hybrid: controller on OKE (always-on), static agent on AKS (when cluster is up). The canonical plan and runbook live in the **hub-docs** repo: `JENKINS-SPLIT-AGENT-PLAN.md` and `JENKINS-SPLIT-AGENT-RUNBOOK.md`.

**Domain cutover complete.** Production Jenkins is at **https://jenkins.canepro.me** (DNS and Ingress point to OKE). The static AKS agent connects to this URL when AKS is up.

**Phase 0 (E1 — free 50GB for Jenkins):** Done in hub repo. Grafana on emptyDir; Grafana PVC removed; 50GB freed for Jenkins on OKE.

**Phase 1 (Jenkins on OKE with HTTPS):** Done. Controller at https://jenkins-oke.canepro.me; TLS and admin login OK; aks-agent node in JCasC (inbound launcher).

**Phase 2 (AKS static agent):** Done. Secret `jenkins-agent-secret` created on AKS; agent manifest deployed via `aks-rocketchat-ops`; pod connects via WebSocket to the controller. Phase 3 (job routing) and Phase 4 (graceful disconnect) done for this repo. **Phase 5 (domain cutover) complete:** production URL is **https://jenkins.canepro.me**.

**OKE parity (controller):** Jenkins controller runs on OKE with Kubernetes plugin, OKE cloud (`oke-kubernetes-cloud`), and static `aks-agent` in JCasC. Dynamic pods spin up on OKE; `agent { kubernetes { ... } }` in Jenkinsfiles works. **Production access:** **https://jenkins.canepro.me** (DNS and Ingress for jenkins.canepro.me point at OKE).

**Phase status**

| Phase | Status |
|-------|--------|
| 0. E1 — Free 50GB | Done |
| 1. OKE — Jenkins Controller | Done |
| 2. AKS — Static Agent | Done |
| 3. Job routing | **Done (this repo)** — OKE cloud runs dynamic pods; **Ops repo:** Azure jobs use `aks-agent`. |
| 4. Graceful disconnect | **Done** — Stop runbook disables aks-agent via API, then stops AKS; use production URL in tfvars. |
| 5. Migration / domain cutover | **Done** — DNS and Ingress for jenkins.canepro.me point at OKE; agent uses https://jenkins.canepro.me. |

**Job routing (Phase 3) — this repo vs ops repo**

| Repo | Job type | Labels | Runs on |
|------|----------|--------|---------|
| **This repo (rocketchat-k8s)** | AKS jobs (repo push, version-check, security, helm) | `aks-agent` | Static AKS agent — terraform-validation, version-check, security-validation, helm-validation use `agent { label 'aks-agent' }` so they run on AKS (Workload Identity; AKS has auto-shutdown so controller is on OKE). |
| **This repo** | Other (e.g. central-observability, portfolio) | terraform, helm, default | OKE Kubernetes cloud (dynamic pods). |
| **Ops repo** | Azure jobs | `aks-agent` | Static AKS agent — same pattern as above. |

---

## Current state (this repo)

### Done

- **Phase 2 – AKS static agent**
  - `ops/manifests/jenkins-static-agent.yaml`: Deployment in namespace `jenkins`, connects to OKE controller at `https://jenkins.canepro.me` via **WebSocket** (HTTPS only; no port 50000). Agent name: `aks-agent`.
  - `ops/manifests/jenkins-agent-rbac.yaml`: Namespace `jenkins` and ServiceAccount `jenkins` with Azure Workload Identity annotations (UAMI `fe3d3d95-fb61-4a42-8d82-ec0852486531`).
  - Both included in `ops/kustomization.yaml`; deployed by ArgoCD app `aks-rocketchat-ops`.
  - **Manual step:** Create Secret `jenkins-agent-secret` in namespace `jenkins` with key `secret` (value = agent secret from OKE Jenkins UI: Manage Jenkins → Nodes → aks-agent → Secret).

- **Cleanup scripts (OKE):** Any script that deletes stale Jenkins agents must **skip** the `aks-agent` node (and e.g. `Nodes` if the API returns it). `aks-agent` is the static AKS agent and must stay. It is defined in JCasC (e.g. hub-docs/GrafanaLocal `helm/jenkins-values.yaml`); if it is removed, reload Configuration as Code or restart the Jenkins pod and it will reappear (offline until AKS is up).

- **Docs**
  - `JENKINS_DEPLOYMENT.md`: Split-agent section (connection method WebSocket/443, manifest locations, hub-docs references).
  - `OPERATIONS.md`: Shutdown/startup procedure and reference to hub-docs runbook.

### Not done (by design or deferred)

- **aks-jenkins ArgoCD app:** Removed. The app `GrafanaLocal/argocd/applications/aks-jenkins.yaml` was deleted; this repo no longer deploys a Jenkins controller on AKS. Controller is on OKE; only the static agent (ops manifests) runs on AKS.

- **Jenkinsfiles (this repo):** Phase 3 complete. AKS-bound pipelines (repo push/PR: terraform, helm; version-check; security-validation) use `agent { label 'aks-agent' }` and run on the static AKS agent. Other pipelines (e.g. central-observability, portfolio) still use OKE dynamic pods.

- **Graceful disconnect (Phase 4):** Done. Stop runbook in `terraform/automation.tf` disables Jenkins `aks-agent` via API (when `jenkins_graceful_disconnect_url` and `jenkins_graceful_disconnect_user` are set and Automation Variable `JenkinsAksAgentDisconnectToken` exists), waits 60s, then stops AKS. See OPERATIONS.md and tfvars.example.

---

## Phase 2 steps (connect AKS static agent)

**Connection info:** The aks-agent **node page** in Jenkins is the connection info. There is no separate "connection page"; the **"Run from agent command line"** block on that node page is what you use to connect the agent. Use the secret and URL from that block for the AKS static agent.

| Item           | Value |
|----------------|--------|
| Secret (K8s)   | From node page "Run from agent command line" block |
| JENKINS_URL    | `https://jenkins.canepro.me/` (production; cutover done) |
| Agent name     | `aks-agent` |
| Launch         | `-webSocket` |

1. **In Jenkins (OKE):** Manage Jenkins → Nodes → aks-agent → open the node page; copy the **secret** from the "Run from agent command line" block.

2. **On AKS:** Create Secret `jenkins-agent-secret` in namespace `jenkins` with key `secret` and that value:
   ```bash
   kubectl create secret generic jenkins-agent-secret -n jenkins \
     --from-literal=secret='<paste-secret-from-node-page-here>'
   ```

3. **Deploy the static agent:** Ensure `aks-rocketchat-ops` is synced so `ops/manifests/jenkins-static-agent.yaml` and `ops/manifests/jenkins-agent-rbac.yaml` are applied. The agent uses `JENKINS_URL=https://jenkins.canepro.me` and connects with `-webSocket`.

4. **Domain cutover is complete:** The agent manifest already uses `https://jenkins.canepro.me`. No further URL change needed.

---

## Static agent image (required for AKS jobs)

The AKS-bound pipelines (terraform, version-check, security-validation, helm) run on the static agent. The default image `jenkins/inbound-agent:latest` only provides the agent JAR and will **not** have Terraform, Azure CLI, helm, kubeconform, or version/security tools. For those jobs to succeed, use a **custom image** that extends the agent and includes:

- Terraform + Azure CLI (for terraform-validation; Workload Identity env vars are already on the deployment)
- helm, kubeconform, yamllint (for helm-validation)
- Tools used by version-check and security-validation (or keep install-at-runtime in their first stages if the image has a package manager)

See `ops/manifests/jenkins-static-agent.yaml` comments. After building and pushing the image, set `spec.template.spec.containers[0].image` to that image and sync `aks-rocketchat-ops`.

---

## Phase 5: Domain cutover — remaining steps

**Short checklist**

| # | Step | Where / what |
|---|------|---------------|
| 1 | Migrate jobs to OKE | Credentials + multibranch (see below). |
| 2 | DNS | Point `jenkins.canepro.me` → OKE LB IP. |
| 3 | Jenkins URL (OKE) | Update Jenkins values for production domain (hub-docs / helm). |
| 4 | AKS agent | This repo: `ops/manifests/jenkins-static-agent.yaml` → `JENKINS_URL=https://jenkins.canepro.me/`; sync ops. |
| 5 | Webhooks | GitHub etc.: `https://jenkins.canepro.me/github-webhook/`. |
| 6 | Retire AKS Jenkins | **Done** — `aks-jenkins.yaml` removed; AKS no longer runs a Jenkins controller. |
| (optional) | Phase 4 URL | `terraform.tfvars`: `jenkins_graceful_disconnect_url = "https://jenkins.canepro.me"`; re-apply. |

After step 4, the static agent on AKS connects to OKE via `jenkins.canepro.me`. After step 6, AKS no longer runs a Jenkins controller.

---

**Step 1: Migrate jobs to OKE (before DNS cutover)**

1a. **Create credentials on OKE Jenkins** (https://jenkins.canepro.me)  
Manage Jenkins → Credentials → System → Global credentials → Add Credentials. Use the **same IDs** so job config and Jenkinsfiles keep working:

| Credential ID         | Type                         | Value / note                |
|-----------------------|------------------------------|-----------------------------|
| github-token          | Secret text or User/password | GitHub PAT                  |
| oci-api-key           | Secret file                  | OCI API private key PEM     |
| oci-s3-access-key     | Secret text                  | OCI S3 access key           |
| oci-s3-secret-key     | Secret text                  | OCI S3 secret key           |
| oci-tenancy-ocid      | Secret text                  | OCI tenancy OCID            |
| oci-user-ocid         | Secret text                  | OCI user OCID               |
| oci-fingerprint       | Secret text                  | OCI API key fingerprint     |
| oci-region            | Secret text                  | e.g. us-ashburn-1           |
| tf-var-compartment-id | Secret text                  | OCI compartment OCID        |
| oci-ssh-public-key    | Secret text                  | SSH public key              |

1b. **Recreate multibranch jobs on OKE**

**GrafanaLocal repo** (from that repo root):

Use OKE Jenkins credentials: `JENKINS_USER=admin` and `JENKINS_PASSWORD` from the OKE `jenkins-admin` secret (or the token that works for the crumb API).

```bash
cd /path/to/GrafanaLocal
export JENKINS_URL="https://jenkins.canepro.me"
export JOB_NAME="GrafanaLocal"
export CONFIG_FILE=".jenkins/job-config.xml"
export JENKINS_USER="admin"
export JENKINS_PASSWORD="<from OKE jenkins-admin secret or token>"
bash .jenkins/create-job.sh
```

Or in Jenkins UI: **New Item** → name `GrafanaLocal` → Multibranch Pipeline → Branch Sources → GitHub, Credentials `github-token`, Repository `Canepro/central-observability-hub-stack` → Build Configuration → Script Path `.jenkins/terraform-validation.Jenkinsfile` → Save.

**rocketchat-k8s** (this repo, from repo root):

Use the **same** OKE Jenkins credentials that worked for GrafanaLocal.

```bash
export JENKINS_URL="https://jenkins.canepro.me"
export JOB_NAME="rocketchat-k8s"
export CONFIG_FILE=".jenkins/job-config.xml"
export JENKINS_USER="admin"
export JENKINS_PASSWORD="<same value you used for GrafanaLocal create-job>"
bash .jenkins/scripts/create-job.sh
```

**Other repos (e.g. ops):** Same pattern: use that repo’s `job-config.xml` and create-job script path; use the same OKE credentials.

1c. **Test a build on OKE before DNS cutover**  
Once jobs are created, trigger a build to verify:
- Dynamic pods spin up on OKE
- Credentials work
- Pipeline completes

---

**Step 2: DNS cutover**

Point `jenkins.canepro.me` to the OKE load balancer IP. Get the IP with:

```bash
kubectl --context oke-cluster get svc -n ingress-nginx -o wide | grep LoadBalancer
```

Then in your DNS provider (Cloudflare, Route53, etc.):

- **Record:** `jenkins.canepro.me`  **Type:** A  **Value:** \<OKE LB IP\>  
  (Example: `141.148.16.227` if that is your current OKE LB IP.)

---

**Step 3: Update Jenkins values + Ingress for production domain (OKE)**

On the OKE side (hub-docs / GrafanaLocal): (1) Add an Ingress for host `jenkins.canepro.me` with TLS (e.g. `k8s/jenkins/jenkins-canepro-ingress.yaml`, cert-manager for `jenkins.canepro.me`). (2) Set Jenkins URL in `helm/jenkins-values.yaml` to `https://jenkins.canepro.me`. (3) Deploy via Argo CD (e.g. `jenkins-ingress-canepro` app). Without this, DNS for jenkins.canepro.me points at OKE but there is no route/cert for that host (SSL error). After sync, wait for the certificate then test: `curl -sI https://jenkins.canepro.me`.

---

7. **Shutdown / startup** (ongoing)  
   **Automated (Phase 4):** If `jenkins_graceful_disconnect_url` and `jenkins_graceful_disconnect_user` are set and `JenkinsAksAgentDisconnectToken` exists in Automation, the stop runbook disables the node, waits 60s, then stops AKS. **Manual:** Follow hub-docs `JENKINS-SPLIT-AGENT-RUNBOOK.md`: before 23:00 stop, put node offline, wait 30–60 s, then run Azure Automation stop. On startup, agent reconnects; bring node back online in Jenkins if it was left offline.

---

## Jobs, pipelines, multibranch, and credentials (from AKS Jenkins)

When moving from the old AKS Jenkins controller to OKE, jobs and credentials must be recreated or migrated. Full detail is in **hub-docs** `JENKINS-SPLIT-AGENT-PLAN.md` §8.1. Summary:

- **Jobs and pipelines**
  - **A. Recreate from Git (recommended):** Use `scripts/create-job.sh` with `JENKINS_URL=https://jenkins.canepro.me` and the same `job-config.xml` to create the multibranch on OKE. Or in the UI: New Item → Multibranch Pipeline, same repo and Script Path. No build history copy.
  - **B. Export/import:** Get job config from AKS (`GET .../job/<name>/config.xml`), create job on OKE and POST the same XML. Credentials must exist on OKE with the same IDs.
  - **C. Full JENKINS_HOME copy:** Copy `jobs/`, `credentials.xml`, credential store from AKS PVC to OKE; only if you need full state and can match plugin versions.

- **Multibranch:** Recreate on OKE (UI or `create-job.sh` with OKE URL). Same branch source, same Script Path (e.g. `.jenkins/terraform-validation.Jenkinsfile`). Create the `github-token` credential on OKE first.

- **Credentials and secrets**
  - On AKS: admin + GitHub token from Azure Key Vault via ESO.
  - On OKE: Recreate with the **same credential IDs** so job config and Jenkinsfiles keep working.
  - Options: (1) Add in Jenkins UI (Manage Jenkins → Credentials) with same IDs; (2) OCI Vault + ESO and bind to Jenkins (e.g. admin via `existingSecret`; GitHub token can stay in UI or be fed from a K8s secret).
  - **Checklist of IDs to recreate:** `github-token`, `admin`, `oci-api-key`, `oci-s3-access-key`, `oci-s3-secret-key`, `oci-ssh-public-key`, and the five OCI Secret text IDs (if used).

- **Order of work:** Create `github-token` (and admin if needed) → recreate multibranch/jobs → create folder/OCI credentials with same IDs → point webhooks to OKE → test → retire AKS Jenkins.

---

## Key files (this repo)

| Area              | File(s) |
|-------------------|---------|
| Agent manifest    | `ops/manifests/jenkins-static-agent.yaml` |
| Agent RBAC        | `ops/manifests/jenkins-agent-rbac.yaml` |
| Kustomization     | `ops/kustomization.yaml` |
| ArgoCD (retired) | `aks-jenkins.yaml` removed — controller on OKE only. |
| Jenkinsfiles (AKS agent) | `.jenkins/terraform-validation.Jenkinsfile`, `.jenkins/version-check.Jenkinsfile`, `.jenkins/security-validation.Jenkinsfile`, `.jenkins/helm-validation.Jenkinsfile` — all use `agent { label 'aks-agent' }`. |
| **Jobs / credentials migration** | `.jenkins/scripts/create-job.sh`, `.jenkins/job-config.xml`, `.jenkins/README.md`, hub-docs §8.1 |
| **Graceful disconnect (Phase 4)** | `terraform/automation.tf` (stop runbook), `terraform/variables.tf` (jenkins_graceful_disconnect_*), Automation Variable `JenkinsAksAgentDisconnectToken` |
| Docs              | `JENKINS_DEPLOYMENT.md`, `OPERATIONS.md` |

---

## Connection method

**WebSocket over 443** is the chosen method. The AKS static agent uses `-webSocket` to `https://jenkins.canepro.me`; no JNLP port 50000 on OKE is required. If you later switch to JNLP, expose 50000 on OKE and change the agent args to connect without `-webSocket`.

---

*Document version: 1.0 — AKS-side plan for split-agent hybrid; canonical plan and runbook in hub-docs.*
