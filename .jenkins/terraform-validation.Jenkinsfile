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
          // Install Azure CLI (required for Azure backend authentication)
          sh '''
            if ! command -v az &> /dev/null; then
              echo "Installing Azure CLI..."
              curl -sL https://aka.ms/InstallAzureCLIDeb | bash
            fi
          '''
          
          // Authenticate to Azure (supports multiple methods)
          sh '''
            if [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_TENANT_ID" ] && [ -n "$AZURE_CLIENT_SECRET" ]; then
              echo "Authenticating with Service Principal..."
              az login --service-principal \
                --username "$AZURE_CLIENT_ID" \
                --password "$AZURE_CLIENT_SECRET" \
                --tenant "$AZURE_TENANT_ID" || true
            elif [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_TENANT_ID" ] && [ -n "$AZURE_FEDERATED_TOKEN_FILE" ]; then
              echo "Authenticating with Workload Identity..."
              az login --federated-token "$(cat $AZURE_FEDERATED_TOKEN_FILE)" \
                --service-principal \
                --username "$AZURE_CLIENT_ID" \
                --tenant "$AZURE_TENANT_ID" || true
            else
              echo "Attempting Managed Identity authentication..."
              az login --identity || echo "Managed Identity authentication failed - backend may use existing credentials"
            fi
          '''
          
          // Initialize with backend configuration (needed for plan to work with state)
          // Backend config matches the setup in terraform/README.md
          sh '''
            terraform init \
              -backend-config="resource_group_name=rg-terraform-state" \
              -backend-config="storage_account_name=tfcaneprostate1" \
              -backend-config="container_name=tfstate" \
              -backend-config="key=aks.terraform.tfstate"
          '''
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
