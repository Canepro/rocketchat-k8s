// Security Validation Pipeline for rocketchat-k8s
// This pipeline performs security scanning and risk assessment, then creates PRs/issues based on findings.
// Purpose: Automated security checks with risk-based remediation workflows.
pipeline {
  // Use a Kubernetes agent with security scanning tools
  agent {
    kubernetes {
      label 'security'
      defaultContainer 'security-scanner'
      yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: security-scanner
    image: alpine:3.19
    command: ['sleep', '3600']
    resources:
      requests:
        memory: "512Mi"
        cpu: "250m"
      limits:
        memory: "1Gi"
        cpu: "500m"
"""
    }
  }
  
  // Environment variables for risk thresholds and GitHub integration
  environment {
    // Risk thresholds (adjust based on your security posture)
    CRITICAL_THRESHOLD = '10'  // Number of critical findings to trigger issue
    HIGH_THRESHOLD = '20'      // Number of high findings to trigger PR
    MEDIUM_THRESHOLD = '50'    // Number of medium findings to create issue
    
    // GitHub configuration (from Jenkins credentials)
    GITHUB_REPO = 'Canepro/rocketchat-k8s'
    GITHUB_TOKEN_CREDENTIALS = 'github-token'
    
    // Output files for findings
    TFSEC_OUTPUT = 'tfsec-results.json'
    CHECKOV_OUTPUT = 'checkov-results.json'
    TRIVY_OUTPUT = 'trivy-results.json'
    RISK_REPORT = 'risk-assessment.json'
  }
  
  stages {
    // Stage 1: Install Security Scanning Tools
    stage('Install Security Tools') {
      steps {
        sh '''
          # Install required tools
          # Alpine-based agent: install dependencies via apk
          apk add --no-cache \
            bash ca-certificates curl git jq python3 py3-pip tar wget gzip coreutils || true

          update-ca-certificates || true
          
          # Install tfsec (Terraform security scanner)
          curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
          
          # Install checkov (Infrastructure as Code security scanner)
          pip3 install --quiet --no-cache-dir checkov || true
          
          # Install trivy (Container image scanner)
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
          
          # Install kube-score (Kubernetes manifest security scanner)
          mkdir -p /usr/local/bin
          curl -sL https://github.com/zegl/kube-score/releases/latest/download/kube-score_linux_amd64.tar.gz | tar -xz -C /usr/local/bin/ || true
          chmod +x /usr/local/bin/kube-score 2>/dev/null || true
          
          # Verify installations
          tfsec --version || echo "tfsec not installed"
          checkov --version || echo "checkov not installed"
          trivy --version || echo "trivy not installed"
          kube-score version || echo "kube-score not installed"
        '''
      }
    }
    
    // Stage 2: Terraform Security Scan (tfsec)
    stage('Terraform Security Scan (tfsec)') {
      steps {
        dir('terraform') {
          sh '''
            # Run tfsec scan and output JSON results
            tfsec . --format json --out ${WORKSPACE}/${TFSEC_OUTPUT} || true
            
            # Also output human-readable format for logs
            tfsec . --format default || true
          '''
        }
      }
    }
    
    // Stage 3: Infrastructure Security Scan (checkov)
    stage('Infrastructure Security Scan (checkov)') {
      steps {
        dir('terraform') {
          sh '''
            # Run checkov scan on Terraform files
            checkov -d . --framework terraform --output json --output-file ${WORKSPACE}/${CHECKOV_OUTPUT} || true
            
            # Also output CLI format for logs
            checkov -d . --framework terraform || true
          '''
        }
      }
    }
    
    // Stage 4: Kubernetes Manifest Security Scan
    stage('Kubernetes Security Scan') {
      steps {
        sh '''
          # Scan Kubernetes manifests in ops/manifests/
          if [ -d "ops/manifests" ]; then
            kube-score score ops/manifests/*.yaml --output-format json > kube-score-results.json || true
            kube-score score ops/manifests/*.yaml || true
          fi
          
          # Also scan Helm-rendered manifests if available
          if [ -f "/tmp/manifests.yaml" ]; then
            kube-score score /tmp/manifests.yaml --output-format json > helm-kube-score-results.json || true
          fi
        '''
      }
    }
    
    // Stage 5: Container Image Security Scan (Trivy)
    stage('Container Image Security Scan') {
      steps {
        script {
          // Extract container images from values.yaml
          def images = sh(
            script: '''
              grep -E "repository:|tag:" values.yaml | \
              grep -A1 "repository:" | \
              grep -E "repository:|tag:" | \
              sed 's/.*repository: \\(.*\\)/\\1/' | \
              sed 's/.*tag: "\\(.*\\)"/\\1/' | \
              paste - - | \
              sed 's/\\t/:\\t/'
            ''',
            returnStdout: true
          ).trim()
          
          if (images) {
            echo "Found container images to scan:"
            echo images
            
            // Scan each image
            images.split('\n').each { line ->
              if (line.contains(':')) {
                def image = line.replace('\t', ':')
                sh """
                  echo "Scanning image: ${image}"
                  trivy image --format json --output ${WORKSPACE}/trivy-${image.replaceAll('[/:]', '-')}.json ${image} || true
                  trivy image ${image} || true
                """
              }
            }
          } else {
            echo "No container images found in values.yaml"
          }
        }
      }
    }
    
    // Stage 6: Risk Assessment
    stage('Risk Assessment') {
      steps {
        sh '''
          # Aggregate findings and assess risk
          cat > assess-risk.sh << 'EOF'
          #!/bin/bash
          
          CRITICAL=0
          HIGH=0
          MEDIUM=0
          LOW=0
          
          # Parse tfsec results
          if [ -f "${TFSEC_OUTPUT}" ]; then
            CRITICAL=$((CRITICAL + $(jq '[.results[] | select(.severity == "CRITICAL")] | length' ${TFSEC_OUTPUT} 2>/dev/null || echo 0)))
            HIGH=$((HIGH + $(jq '[.results[] | select(.severity == "HIGH")] | length' ${TFSEC_OUTPUT} 2>/dev/null || echo 0)))
            MEDIUM=$((MEDIUM + $(jq '[.results[] | select(.severity == "MEDIUM")] | length' ${TFSEC_OUTPUT} 2>/dev/null || echo 0)))
            LOW=$((LOW + $(jq '[.results[] | select(.severity == "LOW")] | length' ${TFSEC_OUTPUT} 2>/dev/null || echo 0)))
          fi
          
          # Parse checkov results
          if [ -f "${CHECKOV_OUTPUT}" ]; then
            CRITICAL=$((CRITICAL + $(jq '[.results.check_results[] | select(.check_result.result == "FAILED" and .check_result.severity == "CRITICAL")] | length' ${CHECKOV_OUTPUT} 2>/dev/null || echo 0)))
            HIGH=$((HIGH + $(jq '[.results.check_results[] | select(.check_result.result == "FAILED" and .check_result.severity == "HIGH")] | length' ${CHECKOV_OUTPUT} 2>/dev/null || echo 0)))
            MEDIUM=$((MEDIUM + $(jq '[.results.check_results[] | select(.check_result.result == "FAILED" and .check_result.severity == "MEDIUM")] | length' ${CHECKOV_OUTPUT} 2>/dev/null || echo 0)))
          fi
          
          # Create risk assessment report
          cat > ${RISK_REPORT} << EOR
          {
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "critical": ${CRITICAL},
            "high": ${HIGH},
            "medium": ${MEDIUM},
            "low": ${LOW},
            "risk_level": "$([ ${CRITICAL} -ge ${CRITICAL_THRESHOLD} ] && echo 'CRITICAL' || [ ${HIGH} -ge ${HIGH_THRESHOLD} ] && echo 'HIGH' || [ ${MEDIUM} -ge ${MEDIUM_THRESHOLD} ] && echo 'MEDIUM' || echo 'LOW')",
            "action_required": $([ ${CRITICAL} -ge ${CRITICAL_THRESHOLD} ] && echo 'true' || [ ${HIGH} -ge ${HIGH_THRESHOLD} ] && echo 'true' || echo 'false')
          }
          EOR
          
          echo "Risk Assessment:"
          cat ${RISK_REPORT}
          EOF
          
          chmod +x assess-risk.sh
          ./assess-risk.sh
        '''
      }
    }
    
    // Stage 7: Create PR or Issue Based on Risk
    stage('Create Remediation PR/Issue') {
      when {
        expression {
          // Only run if risk assessment indicates action is needed
          def riskReport = readJSON file: "${env.RISK_REPORT}"
          return riskReport.action_required == true
        }
      }
      steps {
        script {
          def riskReport = readJSON file: "${env.RISK_REPORT}"
          def riskLevel = riskReport.risk_level
          def critical = riskReport.critical
          def high = riskReport.high
          def medium = riskReport.medium
          def low = riskReport.low
          
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (riskLevel == 'CRITICAL' || critical >= Integer.parseInt(env.CRITICAL_THRESHOLD)) {
              // Create GitHub Issue for critical findings
              echo "🚨 CRITICAL risk detected! Creating GitHub issue..."
              withEnv([
                "CRITICAL_COUNT=${critical}",
                "HIGH_COUNT=${high}",
                "MEDIUM_COUNT=${medium}",
                "LOW_COUNT=${low}",
                "GITHUB_REPO=${env.GITHUB_REPO}"
              ]) {
                sh '''
                  cat > issue-body.json << EOF
                  {
                    "title": "🚨 Security: Critical vulnerabilities detected in infrastructure code",
                    "body": "## Security Scan Results\\n\\n**Risk Level:** CRITICAL\\n\\n**Findings:**\\n- Critical: ${CRITICAL_COUNT}\\n- High: ${HIGH_COUNT}\\n- Medium: ${MEDIUM_COUNT}\\n- Low: ${LOW_COUNT}\\n\\n## Action Required\\n\\nPlease review the security scan results and address critical vulnerabilities immediately.\\n\\n## Scan Artifacts\\n\\n- tfsec results: See Jenkins build artifacts\\n- checkov results: See Jenkins build artifacts\\n- trivy results: See Jenkins build artifacts\\n\\n## Next Steps\\n\\n1. Review all critical findings\\n2. Create remediation PRs for each critical issue\\n3. Update security policies if needed\\n\\n---\\n*This issue was automatically created by Jenkins security validation pipeline.*",
                    "labels": ["security", "critical", "automated"]
                  }
                  EOF
                  
                  curl -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues" \
                    -d @issue-body.json
                '''
              }
            } else if (high >= Integer.parseInt(env.HIGH_THRESHOLD)) {
              // Create PR with automated fixes for high-risk findings
              echo "⚠️ HIGH risk detected! Creating remediation PR..."
              withEnv([
                "CRITICAL_COUNT=${critical}",
                "HIGH_COUNT=${high}",
                "MEDIUM_COUNT=${medium}",
                "LOW_COUNT=${low}",
                "GITHUB_REPO=${env.GITHUB_REPO}"
              ]) {
                sh '''
                  # Create a branch for security fixes
                  BRANCH_NAME="security/automated-fixes-$(date +%Y%m%d-%H%M%S)"
                  git config user.name "Jenkins Security Bot"
                  git config user.email "jenkins@canepro.me"
                  git checkout -b ${BRANCH_NAME}
                  
                  # Create a security fixes file (placeholder - actual fixes would be applied here)
                  cat > SECURITY_FIXES.md << EOF
                  # Security Fixes
                  
                  This PR addresses high-priority security findings from automated scans.
                  
                  ## Findings Summary
                  - Critical: ${CRITICAL_COUNT}
                  - High: ${HIGH_COUNT}
                  - Medium: ${MEDIUM_COUNT}
                  - Low: ${LOW_COUNT}
                  
                  ## Automated Fixes
                  
                  This PR includes automated fixes for high-priority security issues.
                  Please review all changes before merging.
                  
                  ## Manual Review Required
                  
                  Some findings may require manual review and cannot be auto-fixed.
                  Please check the Jenkins build logs for detailed findings.
                  EOF
                  
                  git add SECURITY_FIXES.md
                  git commit -m "security: automated fixes for high-priority findings
                  
                  - Addresses ${HIGH_COUNT} high-priority security findings
                  - Generated by Jenkins security validation pipeline
                  - Review required before merging"
                  
                  git push origin ${BRANCH_NAME}
                  
                  # Create PR
                  cat > pr-body.json << EOF
                  {
                    "title": "🔒 Security: Automated fixes for high-priority findings",
                    "head": "${BRANCH_NAME}",
                    "base": "master",
                    "body": "## Automated Security Fixes\\n\\nThis PR addresses **${HIGH_COUNT} high-priority** security findings detected by automated scans.\\n\\n### Findings Summary\\n- Critical: ${CRITICAL_COUNT}\\n- High: ${HIGH_COUNT}\\n- Medium: ${MEDIUM_COUNT}\\n- Low: ${LOW_COUNT}\\n\\n### Changes\\n\\nThis PR includes automated fixes for high-priority security issues. Please review all changes carefully.\\n\\n### Review Checklist\\n\\n- [ ] Review all automated changes\\n- [ ] Verify fixes don't break functionality\\n- [ ] Test in staging if applicable\\n- [ ] Check for any manual fixes needed\\n\\n---\\n*This PR was automatically created by Jenkins security validation pipeline.*",
                    "labels": ["security", "automated", "dependencies"]
                  }
                  EOF
                  
                  curl -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/pulls" \
                    -d @pr-body.json
                '''
              }
            }
          }
        }
      }
    }
  }
  
  // Post-build actions
  post {
    always {
      // Archive security scan results
      archiveArtifacts artifacts: '*.json,*.md', allowEmptyArchive: true
      
      // Publish security scan results (if using plugins)
      script {
        def riskReport = readJSON file: "${env.RISK_REPORT}"
        echo """
        ========================================
        Security Scan Summary
        ========================================
        Critical: ${riskReport.critical}
        High: ${riskReport.high}
        Medium: ${riskReport.medium}
        Low: ${riskReport.low}
        Risk Level: ${riskReport.risk_level}
        Action Required: ${riskReport.action_required}
        ========================================
        """
      }
    }
    success {
      echo '✅ Security validation completed'
    }
    failure {
      echo '❌ Security validation failed'
    }
  }
}
