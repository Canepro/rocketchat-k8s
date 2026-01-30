# Jenkins Split-Agent Plan (AKS Side)

This document is the **AKS-side** summary of the Jenkins split-agent hybrid: controller on OKE (always-on), static agent on AKS (when cluster is up). The canonical plan and runbook live in the **hub-docs** repo: `JENKINS-SPLIT-AGENT-PLAN.md` and `JENKINS-SPLIT-AGENT-RUNBOOK.md`.

**Phase 0 (E1 — free 50GB for Jenkins):** Done in hub repo. Grafana on emptyDir; Grafana PVC removed; 50GB freed for Jenkins on OKE.

**Phase 1 (Jenkins on OKE with HTTPS):** Done. Controller at https://jenkins-oke.canepro.me; TLS and admin login OK; aks-agent node in JCasC (inbound launcher). Next: Phase 2 — connect AKS static agent.

---

## Current state (this repo)

### Done

- **Phase 2 – AKS static agent**
  - `ops/manifests/jenkins-static-agent.yaml`: Deployment in namespace `jenkins`, connects to OKE controller at `https://jenkins.canepro.me` via **WebSocket** (HTTPS only; no port 50000). Agent name: `aks-agent`.
  - `ops/manifests/jenkins-agent-rbac.yaml`: Namespace `jenkins` and ServiceAccount `jenkins` with Azure Workload Identity annotations (UAMI `fe3d3d95-fb61-4a42-8d82-ec0852486531`).
  - Both included in `ops/kustomization.yaml`; deployed by ArgoCD app `aks-rocketchat-ops`.
  - **Manual step:** Create Secret `jenkins-agent-secret` in namespace `jenkins` with key `secret` (value = agent secret from OKE Jenkins UI: Manage Jenkins → Nodes → aks-agent → Secret).

- **Docs**
  - `JENKINS_DEPLOYMENT.md`: Split-agent section (connection method WebSocket/443, manifest locations, hub-docs references).
  - `OPERATIONS.md`: Shutdown/startup procedure and reference to hub-docs runbook.

### Not done (by design or deferred)

- **aks-jenkins ArgoCD app** (`GrafanaLocal/argocd/applications/aks-jenkins.yaml`): Still present. Remove when the controller is live on OKE and you no longer deploy Jenkins from this repo.

- **Jenkinsfiles:** Still use labels `terraform`, `version-checker`, `security`. Relabel to `aks-agent` at cutover (see Phase 3 below).

- **Graceful disconnect:** Azure Automation stop runbook in `terraform/automation.tf` is not extended. Follow hub-docs runbook manually (or automate later).

---

## Phase 2 steps (connect AKS static agent)

**Connection info:** The aks-agent **node page** in Jenkins is the connection info. There is no separate "connection page"; the **"Run from agent command line"** block on that node page is what you use to connect the agent. Use the secret and URL from that block for the AKS static agent.

| Item           | Value |
|----------------|--------|
| Secret (K8s)   | From node page "Run from agent command line" block |
| JENKINS_URL    | `https://jenkins-oke.canepro.me/` |
| Agent name     | `aks-agent` |
| Launch         | `-webSocket` |

1. **In Jenkins (OKE):** Manage Jenkins → Nodes → aks-agent → open the node page; copy the **secret** from the "Run from agent command line" block.

2. **On AKS:** Create Secret `jenkins-agent-secret` in namespace `jenkins` with key `secret` and that value:
   ```bash
   kubectl create secret generic jenkins-agent-secret -n jenkins \
     --from-literal=secret='<paste-secret-from-node-page-here>'
   ```

3. **Deploy the static agent:** Ensure `aks-rocketchat-ops` is synced so `ops/manifests/jenkins-static-agent.yaml` and `ops/manifests/jenkins-agent-rbac.yaml` are applied. The agent uses `JENKINS_URL=https://jenkins-oke.canepro.me` and connects with `-webSocket`.

4. **After domain cutover:** When you point `jenkins.canepro.me` at OKE, change `JENKINS_URL` in the agent manifest to `https://jenkins.canepro.me` and redeploy (sync ops or restart the agent pod).

---

## Remaining steps (when you cut over)


5. **Optional – Relabel Jenkinsfiles**  
   Before removing the controller from AKS, relabel the four pipelines to `aks-agent` so they run on the static agent:
   - `.jenkins/terraform-validation.Jenkinsfile`
   - `.jenkins/version-check.Jenkinsfile`
   - `.jenkins/security-validation.Jenkinsfile`
   - `.jenkins/` (k8s-manifest-validation Jenkinsfile, if present)
  
   Then run a test job on the static agent.

6. **Cutover**  
   Point GitHub/GitLab webhooks to OKE Jenkins URL. Remove or repurpose `GrafanaLocal/argocd/applications/aks-jenkins.yaml` so the Jenkins controller is no longer deployed on AKS.

7. **Shutdown / startup**  
   Follow hub-docs `JENKINS-SPLIT-AGENT-RUNBOOK.md`: before 23:00 stop, check for running builds on `aks-agent`, put node offline, wait 30–60 s, then run Azure Automation stop. On startup, agent reconnects; bring node back online in Jenkins if it was left offline.

---

## Key files (this repo)

| Area              | File(s) |
|-------------------|---------|
| Agent manifest    | `ops/manifests/jenkins-static-agent.yaml` |
| Agent RBAC        | `ops/manifests/jenkins-agent-rbac.yaml` |
| Kustomization     | `ops/kustomization.yaml` |
| ArgoCD (remove at cutover) | `GrafanaLocal/argocd/applications/aks-jenkins.yaml` |
| Jenkinsfiles (relabel at cutover) | `.jenkins/terraform-validation.Jenkinsfile`, `.jenkins/version-check.Jenkinsfile`, `.jenkins/security-validation.Jenkinsfile` |
| Graceful stop     | `terraform/automation.tf` (optional: extend stop runbook) |
| Docs              | `JENKINS_DEPLOYMENT.md`, `OPERATIONS.md` |

---

## Connection method

**WebSocket over 443** is the chosen method. The AKS static agent uses `-webSocket` to `https://jenkins.canepro.me`; no JNLP port 50000 on OKE is required. If you later switch to JNLP, expose 50000 on OKE and change the agent args to connect without `-webSocket`.

---

*Document version: 1.0 — AKS-side plan for split-agent hybrid; canonical plan and runbook in hub-docs.*
