# GitHub Credentials Setup for Jenkins

Jenkins is hitting GitHub API rate limits because it's using anonymous access. Configure GitHub credentials to fix this.

## Quick Setup (5 minutes)

### Step 1: Get GitHub Token from Key Vault (Azure Cloud Shell)

```bash
# Get the token from Key Vault
GITHUB_TOKEN=$(az keyvault secret show \
  --vault-name aks-canepro-kv-e8d280 \
  --name jenkins-github-token \
  --query value -o tsv)

echo "GitHub Token: $GITHUB_TOKEN"
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

### Step 2: Create Jenkins Credential

**Important:** The GitHub plugin for multibranch pipelines requires **"Username with password"** credentials, not "Secret text". The password field should contain your GitHub Personal Access Token.

1. Go to Jenkins: `https://jenkins.canepro.me`
2. **Manage Jenkins** → **Credentials** → **System** → **Global credentials (unrestricted)**
3. Click **"Add Credentials"**
4. Configure:
   - **Kind**: Username with password
   - **Username**: Your GitHub username (e.g., `your-username`)
   - **Password**: `<paste-token-from-step-1>` (the GitHub Personal Access Token)
   - **ID**: `github-token` (must match exactly - this is what jenkins-values.yaml expects)
   - **Description**: "GitHub Personal Access Token for PR validation"
5. Click **"Create"**

**Note:** If you already created a "Secret text" credential, you need to delete it and create a new "Username with password" credential instead. The GitHub plugin filters out non-"username with password" credentials for multibranch pipelines.

### Step 3: Verify

Trigger a new build. You should see:
- ✅ "Connecting to https://api.github.com with credentials github-token"
- ✅ No more rate limiting messages
- ✅ Builds proceed immediately

## Alternative: Use Kubernetes Secret (If ESO is syncing it)

If External Secrets Operator has synced the token to Kubernetes:

```bash
# Get token from Kubernetes Secret
kubectl get secret jenkins-github -n jenkins -o jsonpath='{.data.token}' | base64 -d
```

Then use that token to create the Jenkins credential (Step 2 above).

## Troubleshooting: Credential Exists But Still Getting Rate Limits

If you already have the credential configured but Jenkins is still using anonymous access:

### 1. Verify GitHub Plugin Configuration

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

### 3. Verify Multibranch Pipeline Configuration

For each multibranch pipeline (portfolio_website-main, GrafanaLocal, etc.):

1. Go to the pipeline in Jenkins
2. Click **"Configure"**
3. Under **"Branch Sources"** → **"GitHub"**
4. Verify **"Credentials"** dropdown shows `github-token` (username with password type)
5. If it's not in the list or shows as filtered out, you need to recreate the credential as "Username with password" (see Step 2 above)
6. Select `github-token` and click **"Save"**

**Important:** Only "Username with password" credentials appear in the dropdown for multibranch pipelines. If your credential doesn't show up, it's likely a "Secret text" type and needs to be recreated.

### 4. Test the Connection

1. In the pipeline configuration, click **"Validate"** next to the GitHub credentials
2. You should see: ✅ "Success"
3. If it fails, verify the token has the correct scopes (`repo`)

### 5. Check Jenkins Logs

If still not working, check Jenkins logs:

```bash
kubectl logs -n jenkins deployment/jenkins --tail=100 | grep -i github
```

Look for errors about credential authentication or API rate limits.
