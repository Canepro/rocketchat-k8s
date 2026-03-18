// Terraform Validation Pipeline for rocketchat-k8s
// This pipeline validates Terraform infrastructure code including plan generation.
// Uses Azure Workload Identity for authentication.
// Runs on the static AKS agent (aks-agent) so it uses AKS Workload Identity and avoids OKE; AKS has auto-shutdown.
pipeline {
  agent { label 'aks-agent' }

  options {
    // Avoid Jenkins' implicit SCM checkout so we can wipe stale workspaces first.
    skipDefaultCheckout(true)
  }
  
  environment {
    // Azure Storage remote backend for Terraform state.
    // Override these in Jenkins job configuration during backend cutover if needed.
    TF_BACKEND_RESOURCE_GROUP = "${env.TF_BACKEND_RESOURCE_GROUP ?: 'rg-canepro-tfstate'}"
    TF_BACKEND_STORAGE_ACCOUNT = "${env.TF_BACKEND_STORAGE_ACCOUNT ?: ''}"
    TF_BACKEND_CONTAINER = "${env.TF_BACKEND_CONTAINER ?: 'tfstate'}"
    TF_BACKEND_KEY = "${env.TF_BACKEND_KEY ?: 'aks.terraform.tfstate'}"
    GITHUB_TOKEN_CREDENTIALS = 'github-token'
    PIPELINEHEALER_BRIDGE_URL_CREDENTIALS = 'pipelinehealer-bridge-url'
    PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS = 'pipelinehealer-bridge-secret'

    // Non-secret defaults so CI plans match interactive plans (override in job config if needed)
    TF_VAR_jenkins_graceful_disconnect_url = "${env.TF_VAR_jenkins_graceful_disconnect_url ?: 'https://jenkins-oke.canepro.me'}"
    TF_VAR_jenkins_graceful_disconnect_user = "${env.TF_VAR_jenkins_graceful_disconnect_user ?: 'admin'}"
    TF_VAR_jenkins_graceful_disconnect_agent_name = "${env.TF_VAR_jenkins_graceful_disconnect_agent_name ?: 'aks-agent'}"
  }
  
  stages {
    // Stage 1: Start from a clean workspace before any PR merge checkout occurs.
    stage('Checkout') {
      steps {
        deleteDir()
        script {
          if (env.CHANGE_ID) {
            withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
              sh '''
                set -eu
                ASKPASS="$(mktemp)"
                cleanup_askpass() {
                  rm -f "$ASKPASS"
                  unset GIT_ASKPASS GIT_TERMINAL_PROMPT
                }
                trap cleanup_askpass EXIT

                cat >"$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "$GITHUB_USER" ;;
  *) printf '%s\n' "$GITHUB_TOKEN" ;;
esac
EOF
                chmod 700 "$ASKPASS"
                export GIT_ASKPASS="$ASKPASS"
                export GIT_TERMINAL_PROMPT=0

                git init .
                git remote add origin https://github.com/Canepro/rocketchat-k8s.git
                git fetch --no-tags --force --progress origin "refs/pull/${CHANGE_ID}/merge"
                git checkout -f FETCH_HEAD
              '''
            }
          } else {
            checkout scm
          }
          env.GIT_COMMIT = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
        }
      }
    }

    // Stage 2: Install Terraform (extract to workspace with Python so no unzip/root needed)
    stage('Setup') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          set -e
          # Ensure we can extract zip without assuming python3 exists.
          if ! command -v python3 >/dev/null 2>&1 && ! command -v unzip >/dev/null 2>&1; then
            if command -v apk >/dev/null 2>&1; then
              apk add --no-cache python3 unzip 2>/dev/null || true
            elif command -v apt-get >/dev/null 2>&1; then
              (apt-get update -qq && apt-get install -y python3 unzip) 2>/dev/null || true
            elif command -v yum >/dev/null 2>&1; then
              yum install -y python3 unzip 2>/dev/null || true
            elif command -v tdnf >/dev/null 2>&1; then
              tdnf install -y python3 unzip 2>/dev/null || true
            fi
          fi
          # Azure CLI (optional): try user install if python3 exists; no root required.
          WORKDIR="${WORKSPACE:-$(pwd)}"
          if ! command -v az >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
            python3 -m pip install --quiet --no-cache-dir --user azure-cli || true
            export PATH="${HOME:-/tmp}/.local/bin:${PATH}"
          fi
          if command -v az >/dev/null 2>&1; then
            echo "Azure CLI available"
            touch "$WORKDIR/.az_available"
          else
            echo "Azure CLI not available; Azure Login stage will be skipped"
            rm -f "$WORKDIR/.az_available"
          fi
          WORKDIR="${WORKSPACE:-$(pwd)}"
          TF_BIN_DIR="${WORKDIR}/.bin"
          mkdir -p "$TF_BIN_DIR"
          TERRAFORM_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | grep -o '"current_version":"[^"]*' | cut -d'"' -f4)
          curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o terraform.zip
          TMP_TF_DIR="$(mktemp -d)"
          if command -v python3 >/dev/null 2>&1; then
            python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" terraform.zip "$TMP_TF_DIR"
          elif command -v unzip >/dev/null 2>&1; then
            unzip -o terraform.zip -d "$TMP_TF_DIR" >/dev/null
          elif command -v jar >/dev/null 2>&1; then
            # Use JDK jar tool if unzip/python3 are unavailable.
            (cd "$TMP_TF_DIR" && jar xf "$WORKDIR/terraform.zip")
          else
            echo "No tool available to extract terraform.zip (python3, unzip, or jar)"
            exit 1
          fi
          if [ ! -f "$TMP_TF_DIR/terraform" ]; then
            echo "Terraform binary not found after extraction"
            exit 1
          fi
          mv "$TMP_TF_DIR/terraform" "$TF_BIN_DIR/terraform"
          rm -rf "$TMP_TF_DIR" terraform.zip
          chmod +x "$TF_BIN_DIR/terraform"
          export PATH="${TF_BIN_DIR}:${PATH}"
          terraform version
SCRIPT
        '''
      }
    }
    
    // Stage 3: Verify Azure Workload Identity
    stage('Verify Azure Auth') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          set -e
          echo "=== Verifying Azure Workload Identity Configuration ==="
          
          # Check required environment variables
          if [ -z "${ARM_CLIENT_ID:-}" ]; then
            echo "ERROR: ARM_CLIENT_ID not set"
            exit 1
          fi
          if [ -z "${ARM_TENANT_ID:-}" ]; then
            echo "ERROR: ARM_TENANT_ID not set"
            exit 1
          fi
          if [ -z "${ARM_SUBSCRIPTION_ID:-}" ]; then
            echo "ERROR: ARM_SUBSCRIPTION_ID not set"
            exit 1
          fi
          if [ -z "${AZURE_FEDERATED_TOKEN_FILE:-}" ]; then
            echo "ERROR: AZURE_FEDERATED_TOKEN_FILE not set"
            exit 1
          fi
          
          # Verify token file exists and is readable
          if [ ! -f "$AZURE_FEDERATED_TOKEN_FILE" ]; then
            echo "ERROR: Token file not found at $AZURE_FEDERATED_TOKEN_FILE"
            exit 1
          fi
          
          echo "✓ Client ID: ${ARM_CLIENT_ID}"
          echo "✓ Tenant ID: ${ARM_TENANT_ID}"
          echo "✓ Subscription ID: ${ARM_SUBSCRIPTION_ID}"
          echo "✓ Token file: ${AZURE_FEDERATED_TOKEN_FILE}"
          echo "✓ Token file size: $(wc -c < $AZURE_FEDERATED_TOKEN_FILE) bytes"
          echo ""
          echo "Workload Identity is configured. Terraform will authenticate using OIDC token."
SCRIPT
        '''
      }
    }
    
    // Stage 4: Format Check
    stage('Terraform Format') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            export PATH="${WORKSPACE}/.bin:${PATH}"
            terraform fmt -check -recursive
SCRIPT
          '''
        }
      }
    }
    
    // Stage 5: Terraform Init & Validate
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            export PATH="${WORKSPACE}/.bin:${PATH}"
            if [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]; then
              export ARM_OIDC_TOKEN_FILE="${AZURE_FEDERATED_TOKEN_FILE}"
            fi
            if [ -z "${TF_BACKEND_STORAGE_ACCOUNT:-}" ]; then
              echo "ERROR: TF_BACKEND_STORAGE_ACCOUNT must be set to the bootstrap output backend_storage_account_name"
              exit 1
            fi
            # Initialize with backend (uses Workload Identity for auth)
            terraform init \
              -backend-config="resource_group_name=${TF_BACKEND_RESOURCE_GROUP}" \
              -backend-config="storage_account_name=${TF_BACKEND_STORAGE_ACCOUNT}" \
              -backend-config="container_name=${TF_BACKEND_CONTAINER}" \
              -backend-config="key=${TF_BACKEND_KEY}" \
              -backend-config="use_oidc=true" \
              -backend-config="use_azuread_auth=true" \
              -backend-config="tenant_id=${ARM_TENANT_ID}" \
              -backend-config="client_id=${ARM_CLIENT_ID}" \
              -backend-config="subscription_id=${ARM_SUBSCRIPTION_ID}"
            
            terraform validate
SCRIPT
          '''
        }
      }
    }
    
    // Stage 6: Prepare tfvars for validation
    stage('Get Variables') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            export PATH="${WORKSPACE}/.bin:${PATH}"
            # Use example file for CI validation (contains placeholder values)
            # Real secrets are never stored in blob storage
            echo "INFO: Using example tfvars for validation (placeholder values)"
            cp terraform.tfvars.example terraform.tfvars
SCRIPT
          '''
        }
      }
    }
    
    // Stage 7: Terraform Plan
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            export PATH="${WORKSPACE}/.bin:${PATH}"
            if [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]; then
              export ARM_OIDC_TOKEN_FILE="${AZURE_FEDERATED_TOKEN_FILE}"
            fi
            terraform plan \
              -no-color \
              -input=false \
              -out=tfplan \
              -detailed-exitcode || PLAN_EXIT=$?
            
            # Exit codes: 0 = no changes, 1 = error, 2 = changes present
            if [ "${PLAN_EXIT:-0}" = "1" ]; then
              echo "Terraform plan failed"
              exit 1
            elif [ "${PLAN_EXIT:-0}" = "2" ]; then
              echo "Changes detected in plan"
            else
              echo "No changes detected"
            fi
SCRIPT
          '''
        }
      }
    }
  }
  
  post {
    always {
      // Archive plan for review
      dir('terraform') {
        sh 'export PATH="${WORKSPACE}/.bin:${PATH}" && terraform show -no-color tfplan > tfplan.txt 2>/dev/null || true'
        archiveArtifacts artifacts: 'tfplan.txt', allowEmptyArchive: true
      }
    }
    cleanup {
      cleanWs()
    }
    success {
      echo '✅ Terraform validation passed'
    }
    failure {
      echo '❌ Terraform validation failed'
      script {
        try {
          withCredentials([
            string(credentialsId: "${env.PIPELINEHEALER_BRIDGE_URL_CREDENTIALS}", variable: 'PH_BRIDGE_URL'),
            string(credentialsId: "${env.PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS}", variable: 'PH_BRIDGE_SECRET'),
          ]) {
            echo 'PipelineHealer bridge: entering failure handler'
            if (fileExists('.jenkins/scripts/send-pipelinehealer-bridge.sh')) {
              def groovyExists = fileExists('.jenkins/scripts/pipelinehealer-bridge-evidence.groovy')
              echo "PipelineHealer bridge: evidence groovy exists=${groovyExists}"
              if (groovyExists) {
                echo 'PipelineHealer bridge: loading Groovy fallback helper'
                def bridgeEvidence = load '.jenkins/scripts/pipelinehealer-bridge-evidence.groovy'
                def result = bridgeEvidence.writeLogExcerpt()
                echo "PipelineHealer bridge: fallback helper returned=${result}"
              }
              echo "PipelineHealer bridge: excerpt file exists=${fileExists("${env.WORKSPACE}/.pipelinehealer-log-excerpt.txt")}"
              sh '''
                set +e
                export PH_REPOSITORY="Canepro/rocketchat-k8s"
                export PH_JOB_NAME="${JOB_NAME}"
                export PH_JOB_URL="${BUILD_URL}"
                export PH_BUILD_NUMBER="${BUILD_NUMBER}"
                PH_BRANCH_VALUE="${GIT_BRANCH:-}"
                if [ -z "${PH_BRANCH_VALUE}" ]; then
                  PH_BRANCH_VALUE="${BRANCH_NAME:-unknown}"
                fi
                export PH_BRANCH="${PH_BRANCH_VALUE}"
                export PH_COMMIT_SHA="${GIT_COMMIT:-}"
                export PH_FAILURE_STAGE="terraform-validation"
                export PH_FAILURE_SUMMARY="Jenkins Terraform validation failed"
                export PH_RESULT="FAILURE"
                if [ -f "${WORKSPACE}/.pipelinehealer-log-excerpt.txt" ]; then
                  export PH_LOG_EXCERPT_FILE="${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
                fi
                bash .jenkins/scripts/send-pipelinehealer-bridge.sh >/dev/null || \
                  echo "⚠️ WARNING: Failed to notify PipelineHealer bridge"
              '''
            } else {
              echo '⚠️ PipelineHealer bridge script unavailable in workspace; skipping bridge notification.'
            }
          }
        } catch (err) {
          echo "⚠️ PipelineHealer bridge credentials not configured; skipping bridge notification."
        }
      }
    }
  }
}
