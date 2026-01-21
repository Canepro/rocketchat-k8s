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
    
    // Stage 3: Plan Generation
    // Generates an execution plan to detect potential issues
    // This is read-only - no changes are applied (CI validation only)
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          // Initialize with backend (needed for plan to work with state)
          sh 'terraform init'
          // Generate plan without color output (better for CI logs)
          // -out=tfplan: save plan for potential later use (not applied by Jenkins)
          sh 'terraform plan -no-color -out=tfplan'
        }
      }
    }
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
