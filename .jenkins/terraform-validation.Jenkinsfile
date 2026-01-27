// Terraform Validation Pipeline for rocketchat-k8s
// This pipeline validates Terraform infrastructure code including plan generation.
// Uses Azure Workload Identity for authentication.
pipeline {
  agent {
    kubernetes {
      label 'terraform-azure'
      defaultContainer 'terraform'
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: jenkins
  containers:
  - name: terraform
    image: mcr.microsoft.com/azure-cli:latest
    command: ['sleep', '3600']
    resources:
      requests:
        memory: "512Mi"
        cpu: "200m"
      limits:
        memory: "1Gi"
        cpu: "1000m"
    env:
    - name: ARM_USE_OIDC
      value: "true"
    - name: ARM_OIDC_TOKEN_FILE_PATH
      value: "/var/run/secrets/azure/tokens/azure-identity-token"
    - name: ARM_TENANT_ID
      value: "c3d431f1-3e02-4c62-a825-79cd8f9e2053"
    - name: ARM_CLIENT_ID
      value: "fe3d3d95-fb61-4a42-8d82-ec0852486531"
    - name: ARM_SUBSCRIPTION_ID
      value: "1c6e2ceb-7310-4193-ab4d-95120348b934"
"""
    }
  }
  
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
              -backend-config="key=terraform.tfstate" \
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
    
    // Stage 5: Download tfvars
    stage('Get Variables') {
      steps {
        dir('terraform') {
          sh '''
            # Download terraform.tfvars from Azure Storage
            az storage blob download \
              --account-name $STORAGE_ACCOUNT \
              --container-name $STORAGE_CONTAINER \
              --name $TFVARS_BLOB \
              --file terraform.tfvars \
              --auth-mode login || {
              echo "WARNING: Could not download tfvars, using example file"
              cp terraform.tfvars.example terraform.tfvars 2>/dev/null || true
            }
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
