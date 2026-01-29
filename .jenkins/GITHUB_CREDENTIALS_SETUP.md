# GitHub Credentials Setup for Jenkins

Jenkins needs authenticated GitHub API access for:
- multibranch scanning + PR status checks
- automated issues/PRs created by scheduled jobs (`version-check-*`, `security-validation-*`)

This repo is designed to provision the GitHub credential **via GitOps** (External Secrets Operator + Kubernetes Credentials Provider), so you shouldn't need to click around Jenkins UI on every rebuild.

## Quick Setup (GitOps-first, recommended)

### Step 1: Store the PAT in Azure Key Vault (Cloud Shell)

```bash
# Get the token from Key Vault
GITHUB_TOKEN=$(az keyvault secret show \
  --vault-name aks-canepro-kv-e8d280 \
  --name jenkins-github-token \
  --query value -o tsv)

echo "GitHub Token retrieved (not printing it)"
```

**If the token doesn't exist in Key Vault**, create a GitHub Personal Access Token:
1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with scopes: `repo` (full control), `admin:repo_hook` (optional)
3. Store it in Key Vault:
   ```bash
   az keyvault secret set \
     --vault-name aks-canepro-kv-e8d280 \
     --name jenkins-github-token \
     --value "<your-github-token>"
   ```

### Step 2: Let ESO sync it into Kubernetes (no Jenkins UI clicks)

This repo already contains an ExternalSecret that syncs the token into the `jenkins` namespace:
- `ops/secrets/externalsecret-jenkins.yaml` → creates/updates `secret/jenkins-github`

That Secret is annotated/labeled so Jenkins’ **Kubernetes Credentials Provider** plugin auto-discovers it as:
- **Type**: Username with password
- **ID**: `github-token`
- **Username**: `jenkins-bot` (placeholder; GitHub PAT auth uses the password field)
- **Password**: the GitHub PAT value

Once the cluster is up and ArgoCD/ESO have synced, `github-token` should appear in Jenkins dropdowns automatically.

### Step 3: Verify

Trigger a new build. You should see:
- ✅ "Connecting to https://api.github.com with credentials github-token"
- ✅ No more rate limiting messages
- ✅ Builds proceed immediately

## Verification

1. Confirm ESO created the Secret:

```bash
kubectl get secret jenkins-github -n jenkins
```

2. Confirm Jenkins can see it:
- Jenkins → **Manage Jenkins** → **Credentials**
- It should show a credential with **ID** `github-token`

## Manual fallback (only if Kubernetes Credentials Provider is not available)

**Important:** The GitHub plugin for multibranch pipelines requires **"Username with password"** credentials, not "Secret text".

Create it in Jenkins UI:
- **Kind**: Username with password
- **ID**: `github-token`
- **Password**: GitHub PAT

(If you created a "Secret text" credential previously, it won’t appear in the multibranch GitHub credential dropdown.)

## Troubleshooting

If you already have the credential configured but Jenkins is still using anonymous access:

### 1. Verify Jenkins GitHub configuration

1. Go to Jenkins: `https://jenkins.canepro.me`
2. **Manage Jenkins** → **Configure System**
3. Scroll to **"GitHub"** section
4. Verify:
   - **GitHub Server** is configured
   - **Credentials** dropdown shows `github-token` selected
   - If not, select `github-token` from the dropdown and click **"Save"**

### 2. Restart Jenkins (If Configuration Changed)

If you updated `jenkins-values.yaml` with the GitHub configuration, Jenkins needs to restart:

```bash
# Restart Jenkins StatefulSet to pick up JCasC configuration
kubectl rollout restart statefulset/jenkins -n jenkins

# Wait for it to be ready
kubectl rollout status statefulset/jenkins -n jenkins
```

**Note:** Jenkins is deployed as a StatefulSet (not a Deployment), so use `statefulset/jenkins` instead of `deployment/jenkins`.

### 2. Verify Multibranch Pipeline Configuration

For each multibranch pipeline (portfolio_website-main, GrafanaLocal, etc.):

1. Go to the pipeline in Jenkins
2. Click **"Configure"**
3. Under **"Branch Sources"** → **"GitHub"**
4. Verify **"Credentials"** dropdown shows `github-token` (username with password type)
5. If it's not in the list or shows as filtered out, you need to recreate the credential as "Username with password" (see Step 2 above)
6. Select `github-token` and click **"Save"**

**Important:** Only "Username with password" credentials appear in the dropdown for multibranch pipelines. If your credential doesn't show up, it's likely a "Secret text" type and needs to be recreated.

### 3. Test the Connection

1. In the pipeline configuration, click **"Validate"** next to the GitHub credentials
2. You should see: ✅ "Success"
3. If it fails, verify the token has the correct scopes (`repo`)

### 4. Check Jenkins Logs

If still not working, check Jenkins logs:

```bash
# Jenkins runs as a StatefulSet in this cluster
kubectl logs -n jenkins statefulset/jenkins --tail=100 | grep -i github
```

Look for errors about credential authentication or API rate limits.
