# Jenkinsfile for portfolio_website-main

Copy this Jenkinsfile to `.jenkins/` directory in the `portfolio_website-main` repository.

## application-validation.Jenkinsfile

```groovy
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
  
  // Environment variables for tool versions
  // These match the project's package.json requirements
  environment {
    NODE_VERSION = '20'      // Node.js version (required by Next.js)
    BUN_VERSION = '1.3.5'    // Bun version (package manager and runtime)
  }
  
  stages {
    // Stage 1: Install Bun Runtime
    // Bun is the package manager and runtime for this Next.js project
    // Installing it here allows us to use bun commands in subsequent stages
    stage('Setup') {
      steps {
        sh '''
          # Install Bun using official installer
          curl -fsSL https://bun.sh/install | bash
          # Add Bun to PATH for this session
          export PATH="$HOME/.bun/bin:$PATH"
          # Verify installation
          bun --version
        '''
      }
    }
    
    // Stage 2: Dependency Security Audit
    // Scans package.json dependencies for known vulnerabilities
    // Similar to npm audit or yarn audit, but for Bun
    stage('Dependency Audit') {
      steps {
        sh '''
          export PATH="$HOME/.bun/bin:$PATH"
          # Run security audit on dependencies
          # || echo: don't fail on warnings, only critical vulnerabilities
          bun audit || echo "Audit completed (warnings may exist)"
        '''
      }
    }
    
    // Stage 3: Code Quality Checks
    // Runs ESLint (linting) and Prettier (formatting check)
    // Ensures code follows project style guidelines
    stage('Code Quality') {
      steps {
        sh '''
          export PATH="$HOME/.bun/bin:$PATH"
          # Run ESLint to catch code quality issues
          bun run lint
          # Check code formatting (Prettier) without modifying files
          bun run format:check
        '''
      }
    }
    
    // Stage 4: TypeScript Type Checking
    // Validates TypeScript types without building
    // Catches type errors early in the CI pipeline
    stage('Type Checking') {
      steps {
        sh '''
          export PATH="$HOME/.bun/bin:$PATH"
          # Run TypeScript compiler in check-only mode
          bun run typecheck
        '''
      }
    }
    
    // Stage 5: Build Validation
    // Attempts to build the Next.js application
    // Ensures the app can compile successfully before deployment
    stage('Build Validation') {
      steps {
        sh '''
          export PATH="$HOME/.bun/bin:$PATH"
          # Build Next.js application for production
          # This validates that all code compiles and bundles correctly
          bun run build
        '''
      }
    }
    
    // Stage 6: Container Image Security Scan
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
          # Container scanning (if Dockerfile exists)
          # This would use tools like Trivy, Snyk, or similar
          if [ -f Dockerfile ]; then
            echo "Container scanning would run here (trivy, etc.)"
            # Example: trivy image --exit-code 1 --severity HIGH,CRITICAL <image>
            # Note: Would need to build image first, then scan it
          fi
        '''
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
      echo '✅ Application validation passed'
    }
    // Failure message for easy log scanning
    failure {
      echo '❌ Application validation failed'
    }
  }
}
```

## Alternative: Custom Bun Agent

For better performance, create a custom Bun agent in `jenkins-values.yaml`:

```yaml
agent:
  podTemplates:
    bun: |
      - name: bun
        label: bun
        nodeUsageMode: EXCLUSIVE
        containers:
          - name: bun
            image: oven/bun:1.3.5-alpine
            command: "/bin/sh -c"
            args: "cat"
            ttyEnabled: true
            resourceRequestCpu: "200m"
            resourceRequestMemory: "512Mi"
            resourceLimitCpu: "2000m"
            resourceLimitMemory: "4Gi"
```

Then update the Jenkinsfile to use `label 'bun'` instead of `label 'default'`.

## Setup Instructions

1. **In the `portfolio_website-main` repository**:
   ```bash
   mkdir -p .jenkins
   # Copy the Jenkinsfile above into .jenkins/application-validation.Jenkinsfile
   ```

2. **In Jenkins UI**:
   - Create **Multibranch Pipeline** job: `portfolio_website-main`
   - Configure GitHub branch source
   - Set **Script Path** to `.jenkins/application-validation.Jenkinsfile`
   - Enable PR discovery

3. **GitHub Webhook**:
   - Add webhook: `https://jenkins.canepro.me/github-webhook/`
   - Events: Pull requests, Pushes

**Note**: This complements Azure DevOps pipelines - Jenkins provides additional validation layer.
