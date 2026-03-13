// Terraform Validation Pipeline for central-observability-hub-stack
// This pipeline validates Terraform infrastructure code for the OKE Hub cluster.
// Purpose: CI validation only - complements existing GitHub Actions for redundancy.
pipeline {
  // Use the 'terraform' Kubernetes agent (Hashicorp Terraform image)
  agent {
    kubernetes {
      label 'terraform'
      defaultContainer 'terraform'
    }
  }

  options {
    // Avoid implicit SCM checkout so the workspace can be wiped first.
    skipDefaultCheckout(true)
  }
  
  // Environment variables for Azure Storage and Key Vault access
  // These can be overridden in Jenkins UI if needed, but defaults are set here
  environment {
    // Azure Key Vault and Storage Account configuration
    AZURE_KEY_VAULT_NAME = 'aks-canepro-kv-e8d280'
    AZURE_STORAGE_ACCOUNT_NAME = 'tfcaneprostate1'
    AZURE_STORAGE_CONTAINER_NAME = 'tfstate'
    AZURE_STORAGE_BLOB_PATH = 'terraform.tfvars'
    AZURE_STORAGE_KEY_SECRET_NAME = 'storage-account-key'
    
    // Azure authentication (using ESO identity)
    AZURE_CLIENT_ID = 'fe3d3d95-fb61-4a42-8d82-ec0852486531'
    AZURE_TENANT_ID = 'c3d431f1-3e02-4c62-a825-79cd8f9e2053'
    PIPELINEHEALER_BRIDGE_URL_CREDENTIALS = 'pipelinehealer-bridge-url'
    PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS = 'pipelinehealer-bridge-secret'
    
    // Note: AZURE_CLIENT_SECRET is not needed if using Workload Identity
    // The Jenkinsfile will automatically detect and use Workload Identity if configured
  }
  
  stages {
    stage('Checkout') {
      steps {
        deleteDir()
        checkout scm
      }
    }

    // Stage 1: Format Check
    // Ensures all Terraform files follow consistent formatting standards
    stage('Terraform Format Check') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            terraform fmt -check -recursive
SCRIPT
          '''
        }
      }
    }
    
    // Stage 2: Syntax Validation
    // Validates Terraform configuration syntax and basic consistency
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            terraform init -backend=false
            terraform validate
SCRIPT
          '''
        }
      }
    }
    
    // Stage 3: Plan Generation (SKIPPED in CI)
    // Plan generation requires OCI authentication which is not available in CI.
    // Format and Validate stages are sufficient for CI validation.
    // Real planning/apply happens in Cloud Shell with proper OCI authentication.
    //
    // NOTE: Plan stage is commented out because:
    // - OCI provider requires proper tenancy/user/fingerprint/key configuration
    // - Jenkins Terraform container is minimal (no OCI CLI/config available)
    // - Format + Validate stages provide sufficient CI validation
    // - Actual planning/apply happens in Cloud Shell with proper OCI auth
    //
    // stage('Terraform Plan') {
    //   steps {
    //     dir('terraform') {
    //       sh 'terraform init'
    //       script {
    //         // ... entire plan stage commented out ...
    //         // OCI authentication required but not available in CI
    //       }
    //     }
    //   }
    // }
  }
  
  post {
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
            sh '''
              set +e
              export PH_REPOSITORY="Canepro/central-observability-hub-stack"
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
              export PH_FAILURE_SUMMARY="Jenkins central observability Terraform validation failed"
              export PH_RESULT="FAILURE"
              if [ -f "${WORKSPACE}/.pipelinehealer-log-excerpt.txt" ]; then
                export PH_LOG_EXCERPT_FILE="${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
              fi
              bash .jenkins/scripts/send-pipelinehealer-bridge.sh >/dev/null || \
                echo "⚠️ WARNING: Failed to notify PipelineHealer bridge"
            '''
          }
        } catch (err) {
          echo "⚠️ PipelineHealer bridge credentials not configured; skipping bridge notification."
        }
      }
    }
  }
}
