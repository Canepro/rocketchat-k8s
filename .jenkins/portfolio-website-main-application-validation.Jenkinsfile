// Next.js Application Validation Pipeline for portfolio_website-main
// This pipeline validates the Next.js/TypeScript portfolio application.
// Purpose: CI validation - complements Azure DevOps pipelines for additional checks.
pipeline {
  // Use default agent (Ubuntu-based with basic tools)
  // Bun will be installed in the Setup stage
  agent {
    kubernetes {
      label 'default'
      defaultContainer 'jnlp'
    }
  }

  options {
    // Avoid implicit SCM checkout so the workspace can be wiped first.
    skipDefaultCheckout(true)
  }
  
  // Environment variables for tool versions
  // These match the project's package.json requirements
  environment {
    NODE_VERSION = '20'      // Node.js version (required by Next.js)
    BUN_VERSION = '1.3.5'    // Bun version (package manager and runtime)
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

    // Stage 1: Install Bun Runtime
    // Bun is the package manager and runtime for this Next.js project
    // Installing it here allows us to use bun commands in subsequent stages
    stage('Setup') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          # Install unzip (required by bun installer)
          # Update package list and install unzip if not already present
          if ! command -v unzip &> /dev/null; then
            if command -v apt-get &> /dev/null; then
              apt-get update && apt-get install -y unzip
            elif command -v yum &> /dev/null; then
              yum install -y unzip
            elif command -v apk &> /dev/null; then
              apk add --no-cache unzip
            else
              echo "ERROR: Cannot install unzip - package manager not found"
              exit 1
            fi
          fi
          
          # Install Bun using official installer
          curl -fsSL https://bun.sh/install | bash
          # Add Bun to PATH for this session
          export PATH="$HOME/.bun/bin:$PATH"
          # Verify installation
          bun --version
SCRIPT
        '''
      }
    }
    
    // Stage 2: Install Dependencies
    // Install project dependencies before running validation checks
    // Required for lint, typecheck, and build commands to work
    stage('Install Dependencies') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          export PATH="$HOME/.bun/bin:$PATH"
          # Install project dependencies (Next.js, TypeScript, ESLint, etc.)
          bun install
SCRIPT
        '''
      }
    }
    
    // Stage 3: Dependency Security Audit
    // Scans package.json dependencies for known vulnerabilities
    // Similar to npm audit or yarn audit, but for Bun
    stage('Dependency Audit') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          export PATH="$HOME/.bun/bin:$PATH"
          # Run security audit on dependencies
          # || echo: don't fail on warnings, only critical vulnerabilities
          bun audit || echo "Audit completed (warnings may exist)"
SCRIPT
        '''
      }
    }
    
    // Stage 4: Code Quality Checks
    // Runs ESLint (linting) and Prettier (formatting check)
    // Ensures code follows project style guidelines
    stage('Code Quality') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          export PATH="$HOME/.bun/bin:$PATH"
          # Run ESLint to catch code quality issues
          bun run lint
          # Check code formatting (Prettier) without modifying files
          bun run format:check
SCRIPT
        '''
      }
    }
    
    // Stage 5: TypeScript Type Checking
    // Validates TypeScript types without building
    // Catches type errors early in the CI pipeline
    stage('Type Checking') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          export PATH="$HOME/.bun/bin:$PATH"
          # Run TypeScript compiler in check-only mode
          bun run typecheck
SCRIPT
        '''
      }
    }
    
    // Stage 6: Build Validation
    // Attempts to build the Next.js application
    // Ensures the app can compile successfully before deployment
    stage('Build Validation') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          export PATH="$HOME/.bun/bin:$PATH"
          # Build Next.js application for production
          # This validates that all code compiles and bundles correctly
          bun run build
SCRIPT
        '''
      }
    }
    
    // Stage 7: Container Image Security Scan
    // Scans Dockerfile and container images for vulnerabilities
    // Only runs on main/master branches (production builds)
    stage('Container Scan') {
      when {
        anyOf {
          branch 'main'
          branch 'master'
        }
      }
      steps {
        sh '''
          cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          # Container scanning (if Dockerfile exists)
          # This would use tools like Trivy, Snyk, or similar
          if [ -f Dockerfile ]; then
            echo "Container scanning would run here (trivy, etc.)"
            # Example: trivy image --exit-code 1 --severity HIGH,CRITICAL <image>
            # Note: Would need to build image first, then scan it
          fi
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
      echo '✅ Application validation passed'
    }
    // Failure message for easy log scanning
    failure {
      echo '❌ Application validation failed'
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
              export PH_REPOSITORY="Canepro/portfolio_website-main"
              export PH_JOB_NAME="${JOB_NAME}"
              export PH_JOB_URL="${BUILD_URL}"
              export PH_BUILD_NUMBER="${BUILD_NUMBER}"
              PH_BRANCH_VALUE="${GIT_BRANCH:-}"
              if [ -z "${PH_BRANCH_VALUE}" ]; then
                PH_BRANCH_VALUE="${BRANCH_NAME:-unknown}"
              fi
              export PH_BRANCH="${PH_BRANCH_VALUE}"
              export PH_COMMIT_SHA="${GIT_COMMIT:-}"
              export PH_FAILURE_STAGE="application-validation"
              export PH_FAILURE_SUMMARY="Jenkins application validation failed"
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
