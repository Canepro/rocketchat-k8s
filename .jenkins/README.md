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
2. Configure GitHub branch source with `github-token` credential
3. Set **Script Path** to `.jenkins/terraform-validation.Jenkinsfile` or `.jenkins/helm-validation.Jenkinsfile`
4. Enable **Discover pull requests from origin**
5. Save and trigger initial scan

## GitHub Webhook

Configure webhook in repository settings:
- **URL**: `https://jenkins.canepro.me/github-webhook/`
- **Events**: Pull requests, Pushes
- **Content type**: `application/json`
