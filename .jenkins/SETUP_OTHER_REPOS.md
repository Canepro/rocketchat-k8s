# Setting Up Jenkins for Other Repositories

This guide helps you copy Jenkins setup files to your other repositories.

## Quick Setup

Run the setup script from the `rocketchat-k8s` repository:

```bash
# In WSL/bash (from rocketchat-k8s directory)
bash .jenkins/setup-other-repos.sh
```

This script will:
1. Copy shared utilities (`create-job.sh`, `test-auth.sh`, etc.) to each repo
2. Copy repo-specific Jenkinsfiles
3. Create `job-config.xml` templates
4. Create README files

## What Gets Copied

### Shared Files (all repos)
- `.jenkins/create-job.sh` - Script to create Jenkins jobs via CLI
- `.jenkins/test-auth.sh` - Script to test Jenkins authentication
- `.jenkins/setup-via-cli.md` - CLI setup documentation
- `.jenkins/README.md` - Repo-specific README

### portfolio_website-main
- `.jenkins/application-validation.Jenkinsfile` - Next.js/Bun validation pipeline
- `.jenkins/job-config.xml` - Jenkins job configuration

### central-observability-hub-stack
- `.jenkins/terraform-validation.Jenkinsfile` - Terraform validation pipeline
- `.jenkins/k8s-manifest-validation.Jenkinsfile` - Kubernetes manifest validation
- `.jenkins/job-config.xml` - Jenkins job configuration (for Terraform)

## Manual Setup (Alternative)

If the script doesn't work, you can manually copy files:

### For portfolio_website-main

```bash
cd /mnt/d/repos/portfolio_website-main
mkdir -p .jenkins

# Copy from rocketchat-k8s
cp /mnt/d/repos/rocketchat-k8s/.jenkins/create-job.sh .jenkins/
cp /mnt/d/repos/rocketchat-k8s/.jenkins/portfolio-website-main-application-validation.Jenkinsfile .jenkins/application-validation.Jenkinsfile

# Make executable
chmod +x .jenkins/create-job.sh
```

### For central-observability-hub-stack

```bash
cd /mnt/d/repos/central-observability-hub-stack
mkdir -p .jenkins

# Copy from rocketchat-k8s
cp /mnt/d/repos/rocketchat-k8s/.jenkins/create-job.sh .jenkins/
cp /mnt/d/repos/rocketchat-k8s/.jenkins/central-observability-hub-stack-terraform-validation.Jenkinsfile .jenkins/terraform-validation.Jenkinsfile
cp /mnt/d/repos/rocketchat-k8s/.jenkins/central-observability-hub-stack-k8s-manifest-validation.Jenkinsfile .jenkins/k8s-manifest-validation.Jenkinsfile

# Make executable
chmod +x .jenkins/create-job.sh
```

## After Copying Files

1. **Commit and push to GitHub**:
   ```bash
   git add .jenkins/
   git commit -m "Add Jenkins CI validation pipelines"
   git push
   ```

2. **Create Jenkins jobs** (when cluster is back):
   ```bash
   # For portfolio_website-main
   cd /mnt/d/repos/portfolio_website-main
   export JENKINS_URL="https://jenkins.canepro.me"
   export JOB_NAME="portfolio_website-main"
   export CONFIG_FILE=".jenkins/job-config.xml"
   bash .jenkins/create-job.sh
   
   # For central-observability-hub-stack
   cd /mnt/d/repos/central-observability-hub-stack
   export JOB_NAME="central-observability-hub-stack"
   bash .jenkins/create-job.sh
   ```

3. **Configure GitHub webhooks** for each repository:
   - URL: `https://jenkins.canepro.me/github-webhook/`
   - Events: Pull requests, Pushes
   - Content type: `application/json`

## Notes

- The `job-config.xml` files are templates - you may need to adjust the repository name or script path
- For `central-observability-hub-stack`, you can create separate jobs for Terraform and K8s manifest validation, or use one job with a parameter
- All Jenkinsfiles use dynamic Kubernetes agents (no need to pre-configure agents)
