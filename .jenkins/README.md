# Jenkins CI Validation Pipelines

This directory contains Jenkinsfiles for CI validation of the `rocketchat-k8s` repository.

## Available Pipelines

### `terraform-validation.Jenkinsfile`
Validates Terraform infrastructure code:
- Format check (`terraform fmt -check`)
- Syntax validation (`terraform validate`)
- Plan generation (`terraform plan`)

**Agent**: `terraform` (Hashicorp Terraform image)

### `helm-validation.Jenkinsfile`
Validates Helm charts and Kubernetes manifests:
- Helm template rendering
- Kubeconform validation
- YAML linting

**Agent**: `helm` (Alpine Helm image with kubectl and kubeconform)

## Usage

These Jenkinsfiles are used by Jenkins Multibranch Pipeline jobs that automatically:
- Discover branches and pull requests
- Run validation on PRs
- Report status back to GitHub

## Setup in Jenkins

1. Create a **Multibranch Pipeline** job named `rocketchat-k8s`
2. **Branch Sources** section:
   - Click **"Add source"** button (at the top of Branch Sources section)
   - Select **"GitHub"** from the dropdown
3. Configure the GitHub branch source:
   - **Repository HTTPS URL**: `https://github.com/Canepro/rocketchat-k8s`
   - **Credentials**: Select `github-token` from dropdown (required for PR status reporting)
   - **Behaviours** (click "Add" to configure):
     - **Discover branches**: Strategy = "Exclude branches that are also filed as PRs"
     - **Discover pull requests from origin**: Strategy = "The current pull request revision"
     - **Trust**: "From users with Admin or Write permission"
3. **Build Configuration**:
   - **Mode**: "by Jenkinsfile"
   - **Script Path**: `.jenkins/terraform-validation.Jenkinsfile` (or `.jenkins/helm-validation.Jenkinsfile`)
     - This is the path relative to the repository root
4. **Save** → **Scan Multibranch Pipeline Now**

### CLI setup (when UI is painful)
Use the repo script which handles CSRF + session cookies:

```bash
# Recommended to run via port-forward to avoid ingress/TLS issues while debugging:
kubectl -n jenkins port-forward pod/jenkins-0 8080:8080
export JENKINS_URL="http://127.0.0.1:8080"

bash .jenkins/create-job.sh
```

## GitHub Webhook

Configure webhook in repository settings:
- **URL**: `https://jenkins.canepro.me/github-webhook/`
- **Events**: Pull requests, Pushes
- **Content type**: `application/json`

## Jenkins UI login

Jenkins admin credentials are stored in Azure Key Vault and synced into Kubernetes via External Secrets Operator.
To retrieve the current credentials:

```bash
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d; echo
```
