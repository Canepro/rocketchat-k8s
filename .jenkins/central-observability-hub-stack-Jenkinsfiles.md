# Jenkinsfiles for central-observability-hub-stack

Copy these Jenkinsfiles to `.jenkins/` directory in the `central-observability-hub-stack` repository.

## terraform-validation.Jenkinsfile

```groovy
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
  
  stages {
    // Stage 1: Format Check
    // Ensures all Terraform files follow consistent formatting standards
    stage('Terraform Format Check') {
      steps {
        dir('terraform') {
          // -check: only check, don't modify files
          // -recursive: check all subdirectories
          sh 'terraform fmt -check -recursive'
        }
      }
    }
    
    // Stage 2: Syntax Validation
    // Validates Terraform configuration syntax and basic consistency
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          // -backend=false: no state file needed for validation
          sh 'terraform init -backend=false'
          // Validate configuration syntax
          sh 'terraform validate'
        }
      }
    }
    
    // Stage 3: Plan Generation
    // Generates execution plan with detailed exit codes
    // -detailed-exitcode: returns 2 if plan would make changes (useful for CI)
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          // Initialize with backend (needed for plan)
          sh 'terraform init'
          // Generate plan with detailed exit codes
          // Exit code 0: no changes, 1: error, 2: changes detected
          sh 'terraform plan -detailed-exitcode -no-color'
        }
      }
    }
  }
  
  post {
    always {
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
```

## k8s-manifest-validation.Jenkinsfile

```groovy
// Kubernetes Manifest Validation Pipeline for central-observability-hub-stack
// This pipeline validates ArgoCD apps, Helm charts, and raw K8s manifests.
// Purpose: CI validation only - ensures all manifests are valid before GitOps sync.
pipeline {
  // Use the 'helm' Kubernetes agent (has Helm, kubectl, kubeconform)
  agent {
    kubernetes {
      label 'helm'
      defaultContainer 'helm'
    }
  }
  
  stages {
    // Stage 1: ArgoCD Application Validation
    // Validates ArgoCD Application CRDs (the GitOps control plane manifests)
    // These define what ArgoCD should deploy and from where
    stage('ArgoCD App Validation') {
      steps {
        sh '''
          # Validate each ArgoCD Application manifest
          # These are the GitOps control plane definitions
          for app in argocd/applications/*.yaml; do
            if [ -f "$app" ]; then
              # -strict: fail on unknown fields or API mismatches
              kubeconform -strict "$app" || exit 1
            fi
          done
        '''
      }
    }
    
    // Stage 2: Helm Chart Validation
    // Renders and validates all Helm charts in the helm/ directory
    // Ensures Helm templates produce valid Kubernetes manifests
    stage('Helm Chart Validation') {
      steps {
        dir('helm') {
          sh '''
            # Find all Helm chart directories with values.yaml
            for chart_dir in */; do
              if [ -f "${chart_dir}values.yaml" ]; then
                chart_name=$(basename "$chart_dir")
                # Render Helm chart to raw Kubernetes manifests
                helm template "$chart_name" "$chart_dir" -f "${chart_dir}values.yaml" > /tmp/"$chart_name"-manifests.yaml
                # Validate rendered manifests against K8s schema
                kubeconform -strict /tmp/"$chart_name"-manifests.yaml || exit 1
              fi
            done
          '''
        }
      }
    }
    
    // Stage 3: Raw Kubernetes Manifest Validation
    // Validates raw Kubernetes manifests in k8s/ directory
    // These are non-Helm manifests (Ingress, ConfigMaps, etc.)
    stage('K8s Manifest Validation') {
      steps {
        sh '''
          # Validate raw Kubernetes manifests (non-Helm)
          # These are typically Ingress, ConfigMaps, Secrets, etc.
          if [ -d "k8s" ]; then
            for manifest in k8s/**/*.yaml; do
              if [ -f "$manifest" ]; then
                # Validate each manifest against K8s API schema
                kubeconform -strict "$manifest" || exit 1
              fi
            done
          fi
        '''
      }
    }
    
    // Stage 4: YAML Linting
    // Checks YAML syntax, indentation, and style consistency
    // Catches formatting issues before they reach the cluster
    stage('YAML Lint') {
      steps {
        sh '''
          # Install yamllint if not available
          apk add --no-cache yamllint || true
          
          # Lint ArgoCD Application manifests
          yamllint -c .yamllint.yaml argocd/ || true
          
          # Lint Helm values files
          yamllint -c .yamllint.yaml helm/ || true
          
          # Lint raw Kubernetes manifests
          yamllint -c .yamllint.yaml k8s/ || true
          # || true: warnings don't fail build, only errors
        '''
      }
    }
  }
  
  post {
    always {
      cleanWs()
    }
    success {
      echo '✅ Kubernetes manifest validation passed'
    }
    failure {
      echo '❌ Kubernetes manifest validation failed'
    }
  }
}
```

## Setup Instructions

1. **In the `central-observability-hub-stack` repository**:
   ```bash
   mkdir -p .jenkins
   # Copy the Jenkinsfiles above into .jenkins/
   ```

2. **In Jenkins UI**:
   - Create **Multibranch Pipeline** job: `central-observability-hub-stack`
   - Configure GitHub branch source
   - Set **Script Path** to `.jenkins/terraform-validation.Jenkinsfile` or `.jenkins/k8s-manifest-validation.Jenkinsfile`
   - Enable PR discovery

3. **GitHub Webhook**:
   - Add webhook: `https://jenkins.canepro.me/github-webhook/`
   - Events: Pull requests, Pushes

**Note**: This runs in parallel with existing GitHub Actions - both provide validation for redundancy.
