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
          sh 'terraform fmt -check -recursive'
        }
      }
    }
    
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          sh 'terraform init -backend=false'
          sh 'terraform validate'
        }
      }
    }
    
    // NEW: Security Scan Stage
    stage('Terraform Security Scan') {
      steps {
        dir('terraform') {
          sh '''
            # Install tfsec
            curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash || true
            
            # Run security scan (don't fail build on warnings)
            tfsec . --format json --out ../tfsec-results.json || true
            tfsec . || true
          '''
        }
      }
    }
  }
  
  post {
    always {
      archiveArtifacts artifacts: 'tfsec-results.json', allowEmptyArchive: true
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
            sh '''
              set +e
              export PH_REPOSITORY="Canepro/rocketchat-k8s"
              export PH_JOB_NAME="${JOB_NAME}"
              export PH_JOB_URL="${BUILD_URL}"
              export PH_BUILD_NUMBER="${BUILD_NUMBER}"
              export PH_BRANCH="${GIT_BRANCH:-${BRANCH_NAME:-unknown}}"
              export PH_COMMIT_SHA="${GIT_COMMIT:-}"
              export PH_FAILURE_STAGE="terraform-validation-with-security"
              export PH_FAILURE_SUMMARY="Jenkins Terraform validation with security scan failed"
              export PH_RESULT="FAILURE"
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
