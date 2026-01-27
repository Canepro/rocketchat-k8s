#!/bin/bash
# Script to copy Jenkins setup files to other repositories
# Usage: bash .jenkins/scripts/setup-other-repos.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROCKETCHAT_K8S_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
JENKINS_SRC_DIR="${ROCKETCHAT_K8S_REPO}/.jenkins"

echo "🚀 Jenkins Multi-Repo Setup Script"
echo "=================================="
echo ""
echo "This script will copy Jenkins files to your other repositories."
echo "Source repo: $ROCKETCHAT_K8S_REPO"
echo ""

# Detect repos location (assuming they're siblings)
REPOS_DIR="$(dirname "$ROCKETCHAT_K8S_REPO")"

if [ ! -d "$REPOS_DIR" ]; then
  echo "❌ Could not find repos directory: $REPOS_DIR"
  echo "Please run this script from the rocketchat-k8s repository."
  exit 1
fi

# Function to copy files to a repo
setup_repo() {
  local REPO_NAME=$1
  local REPO_PATH="$REPOS_DIR/$REPO_NAME"
  local JENKINS_DIR="$REPO_PATH/.jenkins"

  if [ ! -d "$REPO_PATH" ]; then
    echo "⚠️  Repository not found: $REPO_PATH"
    echo "   Skipping $REPO_NAME..."
    return 1
  fi

  echo ""
  echo "📦 Setting up: $REPO_NAME"
  echo "   Path: $REPO_PATH"

  # Create .jenkins directory
  mkdir -p "$JENKINS_DIR"

  # Copy shared utilities
  echo "   Copying shared utilities..."
  cp "$JENKINS_SRC_DIR/scripts/create-job.sh" "$JENKINS_DIR/create-job.sh"
  cp "$JENKINS_SRC_DIR/scripts/test-auth.sh" "$JENKINS_DIR/test-auth.sh" 2>/dev/null || true

  # Make scripts executable
  chmod +x "$JENKINS_DIR/create-job.sh"
  if [ -f "$JENKINS_DIR/test-auth.sh" ]; then
    chmod +x "$JENKINS_DIR/test-auth.sh"
  fi

  echo "   ✅ Shared utilities copied"

  # Repo-specific files
  case "$REPO_NAME" in
    portfolio_website-main)
      echo "   Creating portfolio website Jenkinsfiles..."
      # Copy actual Jenkinsfile
      cp "$JENKINS_SRC_DIR/portfolio-website-main-application-validation.Jenkinsfile" \
         "$JENKINS_DIR/application-validation.Jenkinsfile"

      # Create job config
      cat > "$JENKINS_DIR/job-config.xml" <<'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject plugin="workflow-multibranch@2.27">
  <description>CI validation pipeline for portfolio_website-main repository</description>
  <properties>
    <org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig plugin="pipeline-model-definition@2.2118">
      <dockerLabel></dockerLabel>
      <registry plugin="docker-plugin@1.2.10"/>
    </org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig>
  </properties>
  <folderViews class="jenkins.branch.MultiBranchProjectViewHolder" plugin="branch-api@2.11.2">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </folderViews>
  <healthMetrics>
    <com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric plugin="cloudbees-folder@6.815.v0b_3c1e18b_81">
      <nonRecursive>false</nonRecursive>
    </com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric>
  </healthMetrics>
  <icon class="jenkins.branch.MetadataActionFolderIcon" plugin="branch-api@2.11.2">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </icon>
  <orphanedItemStrategy class="com.cloudbees.hudson.plugins.folder.computed.DefaultOrphanedItemStrategy" plugin="cloudbees-folder@6.815.v0b_3c1e18b_81">
    <pruneDeadBranches>true</pruneDeadBranches>
    <daysToKeep>-1</daysToKeep>
    <numToKeep>-1</numToKeep>
  </orphanedItemStrategy>
  <triggers>
    <com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger plugin="cloudbees-folder@6.815.v0b_3c1e18b_81">
      <spec>H * * * *</spec>
      <interval>3600000</interval>
    </com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger>
  </triggers>
  <sources class="jenkins.branch.MultiBranchProject$BranchSourceList" plugin="branch-api@2.11.2">
    <data>
      <jenkins.branch.BranchSource>
        <source class="org.jenkinsci.plugins.github_branch_source.GitHubSCMSource" plugin="github-branch-source@2.11.5">
          <id>github-portfolio-website-main</id>
          <credentialsId>github-token</credentialsId>
          <repoOwner>Canepro</repoOwner>
          <repository>portfolio_website-main</repository>
          <traits>
            <org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait>
              <strategyId>1</strategyId>
            </org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait>
            <org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait>
              <strategyId>1</strategyId>
            </org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait>
            <org.jenkinsci.plugins.github_branch_source.ForkPullRequestDiscoveryTrait>
              <strategyId>1</strategyId>
              <trust class="org.jenkinsci.plugins.github_branch_source.ForkPullRequestDiscoveryTrait$TrustContributors"/>
            </org.jenkinsci.plugins.github_branch_source.ForkPullRequestDiscoveryTrait>
          </traits>
        </source>
        <strategy class="jenkins.branch.DefaultBranchPropertyStrategy">
          <properties class="empty-list"/>
        </strategy>
      </jenkins.branch.BranchSource>
    </data>
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </sources>
  <factory class="org.jenkinsci.plugins.workflow.multibranch.WorkflowBranchProjectFactory">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
    <scriptPath>.jenkins/application-validation.Jenkinsfile</scriptPath>
  </factory>
</org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject>
EOF
      echo "   ✅ Portfolio website files created"
      ;;

    GrafanaLocal)
      echo "   Creating observability hub Jenkinsfiles..."
      # Copy actual Jenkinsfiles
      cp "$JENKINS_SRC_DIR/central-observability-hub-stack-terraform-validation.Jenkinsfile" \
         "$JENKINS_DIR/terraform-validation.Jenkinsfile"
      cp "$JENKINS_SRC_DIR/central-observability-hub-stack-k8s-manifest-validation.Jenkinsfile" \
         "$JENKINS_DIR/k8s-manifest-validation.Jenkinsfile"

      # Create job config for Terraform validation
      # Note: Local directory is GrafanaLocal, but GitHub repo is central-observability-hub-stack
      cat > "$JENKINS_DIR/job-config.xml" <<'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject plugin="workflow-multibranch@2.27">
  <description>CI validation pipeline for central-observability-hub-stack repository (GrafanaLocal)</description>
  <properties>
    <org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig plugin="pipeline-model-definition@2.2118">
      <dockerLabel></dockerLabel>
      <registry plugin="docker-plugin@1.2.10"/>
    </org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig>
  </properties>
  <folderViews class="jenkins.branch.MultiBranchProjectViewHolder" plugin="branch-api@2.11.2">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </folderViews>
  <healthMetrics>
    <com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric plugin="cloudbees-folder@6.815.v0b_3c1e18b_81">
      <nonRecursive>false</nonRecursive>
    </com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric>
  </healthMetrics>
  <icon class="jenkins.branch.MetadataActionFolderIcon" plugin="branch-api@2.11.2">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </icon>
  <orphanedItemStrategy class="com.cloudbees.hudson.plugins.folder.computed.DefaultOrphanedItemStrategy" plugin="cloudbees-folder@6.815.vb_3c1e18b_81">
    <pruneDeadBranches>true</pruneDeadBranches>
    <daysToKeep>-1</daysToKeep>
    <numToKeep>-1</numToKeep>
  </orphanedItemStrategy>
  <triggers>
    <com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger plugin="cloudbees-folder@6.815.v0b_3c1e18b_81">
      <spec>H * * * *</spec>
      <interval>3600000</interval>
    </com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger>
  </triggers>
  <sources class="jenkins.branch.MultiBranchProject$BranchSourceList" plugin="branch-api@2.11.2">
    <data>
      <jenkins.branch.BranchSource>
        <source class="org.jenkinsci.plugins.github_branch_source.GitHubSCMSource" plugin="github-branch-source@2.11.5">
          <id>github-central-observability-hub-stack</id>
          <credentialsId>github-token</credentialsId>
          <repoOwner>Canepro</repoOwner>
          <repository>central-observability-hub-stack</repository>
          <traits>
            <org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait>
              <strategyId>1</strategyId>
            </org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait>
            <org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait>
              <strategyId>1</strategyId>
            </org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait>
            <org.jenkinsci.plugins.github_branch_source.ForkPullRequestDiscoveryTrait>
              <strategyId>1</strategyId>
              <trust class="org.jenkinsci.plugins.github_branch_source.ForkPullRequestDiscoveryTrait$TrustContributors"/>
            </org.jenkinsci.plugins.github_branch_source.ForkPullRequestDiscoveryTrait>
          </traits>
        </source>
        <strategy class="jenkins.branch.DefaultBranchPropertyStrategy">
          <properties class="empty-list"/>
        </strategy>
      </jenkins.branch.BranchSource>
    </data>
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </sources>
  <factory class="org.jenkinsci.plugins.workflow.multibranch.WorkflowBranchProjectFactory">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
    <scriptPath>.jenkins/terraform-validation.Jenkinsfile</scriptPath>
  </factory>
</org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject>
EOF
      echo "   ✅ Observability hub files created"
      ;;

    *)
      echo "   ⚠️  Unknown repo type, only copying shared utilities"
      ;;
  esac

  # Create README
  cat > "$JENKINS_DIR/README.md" <<EOF
# Jenkins CI Validation for $REPO_NAME

This directory contains Jenkinsfiles for CI validation of the \`$REPO_NAME\` repository.

## Available Pipelines

See the Jenkinsfiles in this directory for available validation pipelines.

## Setup in Jenkins

### Option 1: CLI Setup (Recommended)

\`\`\`bash
# From this repository directory
cd $REPO_NAME
export JENKINS_URL="https://jenkins.canepro.me"
export JOB_NAME="$REPO_NAME"
export CONFIG_FILE=".jenkins/job-config.xml"
bash .jenkins/scripts/create-job.sh
\`\`\`

### Option 2: UI Setup

1. Go to Jenkins UI: https://jenkins.canepro.me
2. Click "New Item"
3. Enter job name: \`$REPO_NAME\`
4. Select "Multibranch Pipeline"
5. Configure GitHub branch source
6. Set Script Path to the appropriate Jenkinsfile (e.g., \`.jenkins/terraform-validation.Jenkinsfile\`)

## GitHub Webhook

Configure webhook in repository settings:
- **URL**: \`https://jenkins.canepro.me/github-webhook/\`
- **Events**: Pull requests, Pushes
- **Content type**: \`application/json\`

## More Information

See [JENKINS_DEPLOYMENT.md](../../rocketchat-k8s/JENKINS_DEPLOYMENT.md) in the \`rocketchat-k8s\` repository (section: **"Jenkins Strategy (CI vs CD)"**) for the rationale and best practices.
EOF

  echo "   ✅ README created"
  echo "   ✅ Setup complete for $REPO_NAME"
}

# Setup each repo
echo "Setting up repositories..."
setup_repo "portfolio_website-main"
setup_repo "GrafanaLocal"

echo ""
echo "✅ All repositories set up!"
echo ""
echo "Next steps:"
echo "1. Review the .jenkins/ directories in each repo"
echo "2. Commit and push the files to GitHub"
echo "3. Create Jenkins jobs using the create-job.sh script or UI"
echo "4. Configure GitHub webhooks for each repository"

