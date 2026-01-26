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
    // Generates an execution plan to detect potential issues (CI validation only)
    //
    // IMPORTANT:
    // - We use -backend=false because the Jenkins terraform container is minimal (no az/curl/bash)
    //   and CI doesn't need state access (applies happen via Azure Cloud Shell only).
    // - We also pass terraform.tfvars.example so Terraform doesn't prompt for required secret vars.
    stage('Terraform Plan') {
      steps {
        // IMPORTANT: This repo configures an Azure backend in `terraform/backend.tf`:
        //   terraform { backend "azurerm" {} }
        //
        // In CI we do NOT have Azure auth/CLI (container is minimal), so we run the plan
        // against the default *local* backend by making a temporary copy and removing
        // the backend.tf file. Real state-aware planning/apply remains Cloud Shell only.
        sh '''
          rm -rf terraform-ci
          cp -R terraform terraform-ci
        '''
        dir('terraform-ci') {
          // Remove backend.tf so Terraform doesn't require backend init.
          // This allows CI validation without Azure credentials.
          sh '''
            rm -f backend.tf
          '''
          sh 'terraform init -backend=false'
          sh 'terraform plan -no-color -input=false -var-file=terraform.tfvars.example'
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
