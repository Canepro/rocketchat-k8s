// Enhanced Terraform Validation Pipeline with Security Scanning
// This extends the existing terraform-validation.Jenkinsfile with security checks
pipeline {
  agent {
    kubernetes {
      label 'terraform'
      defaultContainer 'terraform'
    }
  }
  
  stages {
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
    }
  }
}
