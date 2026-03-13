// Enhanced Terraform Validation Pipeline with Security Scanning
// This extends the existing terraform-validation.Jenkinsfile with security checks
pipeline {
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

  environment {
    PIPELINEHEALER_BRIDGE_URL_CREDENTIALS = 'pipelinehealer-bridge-url'
    PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS = 'pipelinehealer-bridge-secret'
  }
  
  stages {
    stage('Checkout') {
      steps {
        deleteDir()
        checkout scm
      }
    }

    // Existing stages
    stage('Terraform Format Check') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            terraform fmt -check -recursive
SCRIPT
          '''
        }
      }
    }
    
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            terraform init -backend=false
            terraform validate
SCRIPT
          '''
        }
      }
    }
    
    // NEW: Security Scan Stage
    stage('Terraform Security Scan') {
      steps {
        dir('terraform') {
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            # Install tfsec
            curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash || true
            
            # Run security scan (don't fail build on warnings)
            tfsec . --format json --out ../tfsec-results.json || true
            tfsec . || true
SCRIPT
          '''
        }
      }
    }
  }
  
  post {
    always {
      archiveArtifacts artifacts: 'tfsec-results.json', allowEmptyArchive: true
    }
    cleanup {
      cleanWs()
    }
    success {
      echo '✅ Terraform validation and security scan passed'
    }
    failure {
      echo '❌ Terraform validation or security scan failed'
      script {
        try {
          withCredentials([
            string(credentialsId: "${env.PIPELINEHEALER_BRIDGE_URL_CREDENTIALS}", variable: 'PH_BRIDGE_URL'),
            string(credentialsId: "${env.PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS}", variable: 'PH_BRIDGE_SECRET'),
          ]) {
            echo 'PipelineHealer bridge: entering failure handler'
            def groovyExists = fileExists('.jenkins/scripts/pipelinehealer-bridge-evidence.groovy')
            echo "PipelineHealer bridge: evidence groovy exists=${groovyExists}"
            if (groovyExists) {
              echo 'PipelineHealer bridge: loading Groovy fallback helper'
              def bridgeEvidence = load '.jenkins/scripts/pipelinehealer-bridge-evidence.groovy'
              def result = bridgeEvidence.writeLogExcerpt("${env.WORKSPACE}/.pipelinehealer-log-excerpt.txt")
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
              export PH_FAILURE_STAGE="terraform-validation-with-security"
              export PH_FAILURE_SUMMARY="Jenkins Terraform validation with security scan failed"
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
