// Terraform Validation Pipeline for rocketchat-k8s
// This pipeline validates Terraform infrastructure code without applying changes.
// Purpose: CI validation only - ArgoCD handles actual deployments via GitOps.
pipeline {
  // Use the 'terraform' Kubernetes agent (Hashicorp Terraform image)
  // This agent has Terraform pre-installed and ready to use
  agent {
    kubernetes {
      label 'terraform'
      defaultContainer 'terraform'
    }
  }
  
  stages {
    // Stage 1: Format Check
    // Ensures all Terraform files follow consistent formatting standards
    // Fails if files need formatting (enforces code style consistency)
    stage('Terraform Format Check') {
      steps {
        dir('terraform') {
          // -check flag: only check formatting, don't modify files
          // -recursive: check all subdirectories
          sh 'terraform fmt -check -recursive'
        }
      }
    }
    
    // Stage 2: Syntax Validation
    // Validates Terraform configuration syntax and basic consistency
    // Uses -backend=false to avoid needing actual backend credentials
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          // Initialize without backend (no state file needed for validation)
          sh 'terraform init -backend=false'
          // Validate configuration syntax and internal consistency
          sh 'terraform validate'
        }
      }
    }
    
    // Stage 3: Plan Generation (SKIPPED in CI)
    // Plan generation requires Azure authentication which is not available in CI.
    // Format and Validate stages are sufficient for CI validation.
    // Real planning/apply happens in Azure Cloud Shell with proper authentication.
    //
    // NOTE: Plan stage is commented out because:
    // - Terraform provider requires Azure CLI (`az`) for authentication
    // - Jenkins Terraform container is minimal (no Azure CLI installed)
    // - Format + Validate stages provide sufficient CI validation
    // - Actual planning/apply happens in Cloud Shell with proper auth
    //
    // stage('Terraform Plan') {
    //   steps {
    //     sh '''
    //       rm -rf terraform-ci
    //       cp -R terraform terraform-ci
    //     '''
    //     dir('terraform-ci') {
    //       sh 'rm -f backend.tf'
    //       sh 'terraform init -backend=false'
    //       sh 'terraform plan -no-color -input=false -var-file=terraform.tfvars.example'
    //     }
    //   }
    // }
  }
  
  // Post-build actions: cleanup and status reporting
  post {
    // Always clean workspace after build (free up disk space)
    always {
      cleanWs()
    }
    // Success message for easy log scanning
    success {
      echo '✅ Terraform validation passed'
    }
    // Failure message for easy log scanning
    failure {
      echo '❌ Terraform validation failed'
    }
  }
}
