// Terraform Validation Pipeline for rocketchat-k8s
// This pipeline validates Terraform infrastructure code including plan generation.
// Uses Azure Workload Identity for authentication.
// Runs on the static AKS agent (aks-agent) so it uses AKS Workload Identity and avoids OKE; AKS has auto-shutdown.
pipeline {
  agent { label 'aks-agent' }
  
  environment {
    // Azure Storage for tfvars
    STORAGE_ACCOUNT = 'tfcaneprostate1'
    STORAGE_CONTAINER = 'tfstate'
    TFVARS_BLOB = 'terraform.tfvars'
  }
  
  stages {
    // Stage 1: Install Terraform
    stage('Setup') {
      steps {
        sh '''
          # Install Terraform on Mariner Linux (Azure CLI image)
          # Mariner uses tdnf package manager
          tdnf install -y unzip 2>/dev/null || yum install -y unzip 2>/dev/null || true
          
          TERRAFORM_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | grep -o '"current_version":"[^"]*' | cut -d'"' -f4)
          curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o terraform.zip
          unzip -o terraform.zip -d /usr/local/bin/
          rm terraform.zip
          terraform version
        '''
      }
    }
    
    // Stage 2: Azure Authentication
    stage('Azure Login') {
      steps {
        sh '''
          # Login using Workload Identity (federated token)
          az login --federated-token "$(cat $AZURE_FEDERATED_TOKEN_FILE)" \
            --service-principal \
            -u $ARM_CLIENT_ID \
            -t $ARM_TENANT_ID || {
            echo "Workload Identity login failed, trying managed identity..."
            az login --identity --client-id $ARM_CLIENT_ID
          }
          
          # Set subscription
          az account set --subscription $ARM_SUBSCRIPTION_ID
          az account show
        '''
      }
    }
    
    // Stage 3: Format Check
    stage('Terraform Format') {
      steps {
        dir('terraform') {
          sh 'terraform fmt -check -recursive'
        }
      }
    }
    
    // Stage 4: Terraform Init & Validate
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          sh '''
            # Initialize with backend (uses Workload Identity for auth)
            terraform init \
              -backend-config="resource_group_name=rg-terraform-state" \
              -backend-config="storage_account_name=${STORAGE_ACCOUNT}" \
              -backend-config="container_name=${STORAGE_CONTAINER}" \
              -backend-config="key=aks.terraform.tfstate" \
              -backend-config="use_oidc=true" \
              -backend-config="use_azuread_auth=true" \
              -backend-config="tenant_id=${ARM_TENANT_ID}" \
              -backend-config="client_id=${ARM_CLIENT_ID}" \
              -backend-config="subscription_id=${ARM_SUBSCRIPTION_ID}"
            
            terraform validate
          '''
        }
      }
    }
    
    // Stage 5: Prepare tfvars for validation
    stage('Get Variables') {
      steps {
        dir('terraform') {
          sh '''
            # Use example file for CI validation (contains placeholder values)
            # Real secrets are never stored in blob storage
            echo "INFO: Using example tfvars for validation (placeholder values)"
            cp terraform.tfvars.example terraform.tfvars
          '''
        }
      }
    }
    
    // Stage 6: Terraform Plan
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          sh '''
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
          '''
        }
      }
    }
  }
  
  post {
    always {
      // Archive plan for review
      dir('terraform') {
        sh 'terraform show -no-color tfplan > tfplan.txt 2>/dev/null || true'
        archiveArtifacts artifacts: 'tfplan.txt', allowEmptyArchive: true
      }
      cleanWs()
    }
    success {
      echo '✅ Terraform validation passed'
    }
    failure {
      echo '❌ Terraform validation failed'
    }
  }
}
