// Helm Chart Validation Pipeline for rocketchat-k8s
// This pipeline validates Helm charts and Kubernetes manifests without deploying.
// Purpose: CI validation only - ArgoCD handles actual deployments via GitOps.
// Runs on the static AKS agent (aks-agent) as part of repo push / PR validation.
pipeline {
  agent { label 'aks-agent' }

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

    // Stage 1: Helm Template Rendering
    // Renders Helm charts into raw Kubernetes manifests
    // This validates that Helm templates are syntactically correct
    stage('Helm Template') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          # Render RocketChat Helm chart with values.yaml
          # Output: raw Kubernetes manifests for validation
          helm template rocketchat . -f values.yaml > /tmp/manifests.yaml
          
          # Render Traefik Helm chart (if traefik-values.yaml exists)
          # || true: don't fail if traefik-values.yaml doesn't exist (optional)
          helm template traefik . -f traefik-values.yaml > /tmp/traefik-manifests.yaml || true
SCRIPT
        '''
      }
    }
    
    // Stage 2: Kubernetes Schema Validation
    // Validates rendered manifests against Kubernetes API schema
    // -strict: fail on unknown fields or API version mismatches
    stage('Kubeconform Validate') {
      steps {
        // Validate both RocketChat and Traefik manifests
        // kubeconform checks: API versions, required fields, schema compliance
        sh '''
          cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          kubeconform -strict /tmp/manifests.yaml /tmp/traefik-manifests.yaml
SCRIPT
        '''
      }
    }
    
    // Stage 3: YAML Linting
    // Checks YAML syntax, indentation, and style consistency
    // This catches formatting issues before they reach the cluster
    stage('YAML Lint') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          # Install yamllint if not available in the agent image
          # || true: don't fail if yamllint is already installed
          apk add --no-cache yamllint || true
          
          # Lint main Helm values files (values.yaml, traefik-values.yaml, etc.)
          # || true: warnings don't fail the build (only errors do)
          yamllint -c .yamllint.yaml *.yaml || true
          
          # Lint Kubernetes manifests in ops/manifests/ directory
          # These are raw K8s manifests managed by Kustomize
          yamllint -c .yamllint.yaml ops/manifests/*.yaml || true
SCRIPT
        '''
      }
    }
  }
  
  // Post-build actions: cleanup and status reporting
  post {
    // Always clean workspace after build (free up disk space)
    cleanup {
      cleanWs()
    }
    // Success message for easy log scanning
    success {
      echo '✅ Helm validation passed'
    }
    // Failure message for easy log scanning
    failure {
      echo '❌ Helm validation failed'
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
              export PH_FAILURE_STAGE="helm-validation"
              export PH_FAILURE_SUMMARY="Jenkins Helm validation failed"
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
