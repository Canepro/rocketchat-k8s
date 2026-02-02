// Security Validation Pipeline for rocketchat-k8s
// This pipeline performs security scanning and risk assessment, then creates PRs/issues based on findings.
// Purpose: Automated security checks with risk-based remediation workflows.
// Runs on the static AKS agent (aks-agent); AKS has auto-shutdown so controller lives on OKE.
pipeline {
  agent { label 'aks-agent' }
  
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
            bash ca-certificates curl git jq python3 py3-pip tar wget gzip coreutils yq || true

          update-ca-certificates || true
          
          # Install tfsec (Terraform security scanner) - pinned version, binary from release with checksum verification (no install script from master)
          TFSEC_VERSION="v1.28.14"
          curl -fsSL -o /tmp/tfsec-linux-amd64 "https://github.com/aquasecurity/tfsec/releases/download/${TFSEC_VERSION}/tfsec-linux-amd64"
          curl -fsSL -o /tmp/tfsec_checksums.txt "https://github.com/aquasecurity/tfsec/releases/download/${TFSEC_VERSION}/tfsec_checksums.txt"
          (cd /tmp && grep "tfsec-linux-amd64" tfsec_checksums.txt | grep -v checkgen | sha256sum -c -)
          chmod +x /tmp/tfsec-linux-amd64 && mv /tmp/tfsec-linux-amd64 /usr/local/bin/tfsec
          rm -f /tmp/tfsec_checksums.txt
          
          # Install checkov (Infrastructure as Code security scanner) - pinned version
          # Alpine uses PEP-668 "externally managed" Python; install into a venv.
          CHECKOV_VERSION="3.2.499"
          python3 -m venv /tmp/checkov-venv || true
          if [ -f /tmp/checkov-venv/bin/activate ]; then
            . /tmp/checkov-venv/bin/activate
            pip install --quiet --no-cache-dir "checkov==${CHECKOV_VERSION}" || true
            deactivate || true
            ln -sf /tmp/checkov-venv/bin/checkov /usr/local/bin/checkov || true
          fi
          
          # Install trivy (Container image scanner) - pinned version, binary from release with checksum verification (no install script from main)
          TRIVY_VERSION="0.54.0"
          curl -fsSL -o /tmp/trivy.tar.gz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
          curl -fsSL -o /tmp/trivy_checksums.txt "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_checksums.txt"
          (cd /tmp && grep "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" trivy_checksums.txt | sha256sum -c -)
          tar -xzf /tmp/trivy.tar.gz -C /tmp
          mv /tmp/trivy /usr/local/bin/trivy 2>/dev/null || mv /tmp/trivy_${TRIVY_VERSION}_Linux-64bit/trivy /usr/local/bin/trivy
          chmod +x /usr/local/bin/trivy
          rm -f /tmp/trivy.tar.gz /tmp/trivy_checksums.txt
          rm -rf /tmp/trivy_${TRIVY_VERSION}_Linux-64bit 2>/dev/null || true
          
          # Install kube-score (Kubernetes manifest security scanner) - pinned version with checksum verification
          KUBE_SCORE_VERSION="1.20.0"
          mkdir -p /usr/local/bin
          apk add --no-cache kube-score 2>/dev/null || true
          if ! command -v kube-score >/dev/null 2>&1; then
            curl -fsSL -o /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VERSION}/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz"
            curl -fsSL -o /tmp/kube-score_checksums.txt "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VERSION}/checksums.txt"
            (cd /tmp && grep "kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz" kube-score_checksums.txt | sha256sum -c -)
            tar -xzf /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz -C /tmp
            mv /tmp/kube-score /usr/local/bin/ 2>/dev/null || mv /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64/kube-score /usr/local/bin/
            chmod +x /usr/local/bin/kube-score
            rm -f /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz /tmp/kube-score_checksums.txt
            rm -rf /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64 2>/dev/null || true
          fi
          
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
          if [ -d "ops/manifests" ] && command -v kube-score >/dev/null 2>&1; then
            kube-score score ops/manifests/*.yaml --output-format json > kube-score-results.json || true
            kube-score score ops/manifests/*.yaml || true
          elif [ -d "ops/manifests" ]; then
            echo "kube-score not installed; skipping Kubernetes manifest scan"
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
              set -e

              # Preferred: yq (robust YAML parsing)
              if command -v yq >/dev/null 2>&1; then
                REPO="$(yq -r '.image.repository // ""' values.yaml 2>/dev/null | sed 's/#.*$//' | xargs || true)"
                TAG="$(yq -r '.image.tag // ""' values.yaml 2>/dev/null | sed 's/#.*$//' | xargs || true)"
                [ "$REPO" = "null" ] && REPO=""
                [ "$TAG" = "null" ] && TAG=""
              else
                # Fallback: grep/sed (strip inline comments)
                REPO="$(grep -E '^\\s*repository:' values.yaml | head -1 | sed 's/.*repository:\\s*//' | sed 's/#.*$//' | xargs || true)"
                TAG="$(grep -E '^\\s*tag:' values.yaml | head -1 | sed 's/.*tag:\\s*\"\\{0,1\\}\\([^\"#]*\\)\"\\{0,1\\}.*/\\1/' | sed 's/#.*$//' | xargs || true)"
              fi

              if [ -n "$REPO" ] && [ -n "$TAG" ]; then
                echo "${REPO}:${TAG}"
              fi
            ''',
            returnStdout: true
          ).trim()
          
          if (images) {
            echo "Found container images to scan:"
            echo images
            
            // Scan each image
            images.split('\n').each { line ->
              if (line.contains(':')) {
                def image = line.trim()
                sh """
                  echo "Scanning image: ${image}"
                  trivy image --format json --output ${WORKSPACE}/trivy-${image.replaceAll('[/: ]', '-')}.json ${image} || true
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
        script {
          int tfsecCritical = 0
          int tfsecHigh = 0
          int tfsecMedium = 0
          int tfsecLow = 0

          int checkovCritical = 0
          int checkovHigh = 0
          int checkovMedium = 0
          int checkovLow = 0

          // tfsec: { results: [ { severity: "CRITICAL|HIGH|MEDIUM|LOW", ... }, ... ] }
          if (fileExists(env.TFSEC_OUTPUT)) {
            try {
              def tfsec = readJSON file: env.TFSEC_OUTPUT
              def results = (tfsec?.results instanceof List) ? tfsec.results : []
              tfsecCritical = results.count { it?.severity == 'CRITICAL' }
              tfsecHigh = results.count { it?.severity == 'HIGH' }
              tfsecMedium = results.count { it?.severity == 'MEDIUM' }
              tfsecLow = results.count { it?.severity == 'LOW' }
            } catch (err) {
              echo "WARN: Unable to parse ${env.TFSEC_OUTPUT}: ${err}"
            }
          }

          // checkov output formats vary. We count FAILED checks; if severity missing, treat as MEDIUM.
          if (fileExists(env.CHECKOV_OUTPUT)) {
            try {
              def checkov = readJSON file: env.CHECKOV_OUTPUT
              def failed = []

              if (checkov instanceof Map) {
                if (checkov?.results?.check_results instanceof List) {
                  failed = checkov.results.check_results.findAll { it?.check_result?.result == 'FAILED' }
                } else if (checkov?.results?.failed_checks instanceof List) {
                  failed = checkov.results.failed_checks
                } else if (checkov?.failed_checks instanceof List) {
                  failed = checkov.failed_checks
                }
              } else if (checkov instanceof List) {
                checkov.each { rep ->
                  if (rep?.results?.failed_checks instanceof List) {
                    failed.addAll(rep.results.failed_checks)
                  } else if (rep?.results?.check_results instanceof List) {
                    failed.addAll(rep.results.check_results.findAll { it?.check_result?.result == 'FAILED' })
                  }
                }
              }

              failed.each { item ->
                def sev = (item?.check_result?.severity ?: item?.severity)
                if (sev == 'CRITICAL') {
                  checkovCritical++
                } else if (sev == 'HIGH') {
                  checkovHigh++
                } else if (sev == 'MEDIUM') {
                  checkovMedium++
                } else if (sev == 'LOW') {
                  checkovLow++
                } else {
                  // Many checkov checks don't include severity; treat as MEDIUM for reporting.
                  checkovMedium++
                }
              }
            } catch (err) {
              echo "WARN: Unable to parse ${env.CHECKOV_OUTPUT}: ${err}"
            }
          }

          int critical = tfsecCritical + checkovCritical
          int high = tfsecHigh + checkovHigh
          int medium = tfsecMedium + checkovMedium
          int low = tfsecLow + checkovLow

          // User intent: report always, issue for critical, PR for non-critical.
          String riskLevel = (critical > 0) ? 'CRITICAL' : ((high > 0) ? 'HIGH' : ((medium > 0) ? 'MEDIUM' : 'LOW'))
          boolean actionRequired = (critical > 0 || high > 0 || medium > 0)

          def report = [
            timestamp: sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim(),
            critical: critical,
            high: high,
            medium: medium,
            low: low,
            risk_level: riskLevel,
            action_required: actionRequired
          ]

          writeJSON file: env.RISK_REPORT, json: report
          echo "Risk Assessment: ${report}"

          // Never fail the build due to findings
          currentBuild.result = 'SUCCESS'
        }
      }
    }
    
    // Stage 7: Issues only. One canonical issue "Security: automated scan findings"; find → add comment; create only if it doesn't exist.
    stage('Create/Update Security Findings Issue') {
      steps {
        script {
          if (!fileExists(env.RISK_REPORT)) {
            echo "No ${env.RISK_REPORT} found; skipping."
            return
          }
          def riskReport = readJSON file: "${env.RISK_REPORT}"
          def riskLevel = riskReport.risk_level
          def critical = riskReport.critical
          def high = riskReport.high
          def medium = riskReport.medium
          def low = riskReport.low
          if (riskReport.action_required != true) {
            echo "✅ No remediation needed (risk_level=${riskLevel})."
            return
          }
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (!env.GITHUB_TOKEN?.trim()) {
              echo "⚠️ GitHub token is empty; skipping."
              return
            }
            withEnv([
              "RISK_LEVEL=${riskLevel}",
              "CRITICAL_COUNT=${critical}",
              "HIGH_COUNT=${high}",
              "MEDIUM_COUNT=${medium}",
              "LOW_COUNT=${low}",
              "GITHUB_REPO=${env.GITHUB_REPO}"
            ]) {
              sh '''
                set -e
                WORKDIR="${WORKSPACE:-$(pwd)}"
                ISSUE_TITLE="Security: automated scan findings"
                ensure_label() {
                  LABEL_JSON=$(jq -n --arg name "$1" --arg color "$2" '{name:$name,color:$color}')
                  curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/labels/$1" >/dev/null 2>&1 && return 0
                  if ! curl -fsSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/labels" -d "$LABEL_JSON" >/dev/null 2>&1; then echo "⚠️ WARNING: Failed to create label $1"; fi
                }
                ensure_label "security" "d73a4a"
                ensure_label "automated" "0e8a16"
                [ "$RISK_LEVEL" = "CRITICAL" ] && ensure_label "critical" "b60205"

                ISSUE_LIST_JSON=$(curl -fsSL \
                  -H "Authorization: token ${GITHUB_TOKEN}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=security,automated&per_page=100" \
                  || echo '[]')
                EXISTING_ISSUE_NUMBER=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].number // empty' 2>/dev/null || true)
                EXISTING_ISSUE_URL=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].html_url // empty' 2>/dev/null || true)

                COMMENT_BODY=$(jq -n --arg build "${BUILD_URL}" --arg crit "$CRITICAL_COUNT" --arg h "$HIGH_COUNT" --arg m "$MEDIUM_COUNT" --arg l "$LOW_COUNT" --arg risk "$RISK_LEVEL" \
                  '{body:("## Security scan results\n\nBuild: " + $build + "\n\n**Risk level:** " + $risk + "\n\n**Findings:**\n- Critical: " + $crit + "\n- High: " + $h + "\n- Medium: " + $m + "\n- Low: " + $l + "\n\nArtifacts: " + $build + "artifact/\n\n(De-dupe: comment on existing issue.)")}')
                if [ -n "${EXISTING_ISSUE_NUMBER}" ]; then
                  if ! curl -fsSL -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues/${EXISTING_ISSUE_NUMBER}/comments" \
                    -d "$COMMENT_BODY" >/dev/null 2>&1; then
                    echo "⚠️ WARNING: Failed to add comment to issue #${EXISTING_ISSUE_NUMBER}"
                  fi
                  echo "Updated existing issue: ${EXISTING_ISSUE_URL}"
                  exit 0
                fi

                LABELS_JSON="[\"security\",\"automated\"]"
                [ "$RISK_LEVEL" = "CRITICAL" ] && LABELS_JSON="[\"security\",\"automated\",\"critical\"]"
                ISSUE_BODY_JSON=$(jq -n --arg title "$ISSUE_TITLE" --arg risk "$RISK_LEVEL" --arg crit "$CRITICAL_COUNT" --arg h "$HIGH_COUNT" --arg m "$MEDIUM_COUNT" --arg l "$LOW_COUNT" \
                  --argjson labels "$LABELS_JSON" \
                  '{title:$title, body:("## Security scan results\n\n**Risk level:** " + $risk + "\n\n**Findings:**\n- Critical: " + $crit + "\n- High: " + $h + "\n- Medium: " + $m + "\n- Low: " + $l + "\n\n## Action required\n\nReview scan results and address findings. Artifacts: see Jenkins build.\n\n---\n*Automated by Jenkins security validation pipeline.*"), labels:$labels}')
                echo "$ISSUE_BODY_JSON" > "$WORKDIR/security-issue-body.json"
                if ! curl -sS -X POST \
                  -H "Authorization: token ${GITHUB_TOKEN}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "https://api.github.com/repos/${GITHUB_REPO}/issues" \
                  -d @"$WORKDIR/security-issue-body.json" >/dev/null 2>&1; then
                  echo "⚠️ WARNING: Failed to create security findings issue"
                fi
              '''
            }
          }
        }
      }
    }
  }
  
  post {
    always {
      archiveArtifacts artifacts: '*.json,*.md', allowEmptyArchive: true
      script {
        if (fileExists(env.RISK_REPORT)) {
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
        } else {
          echo "Security Scan Summary: ${env.RISK_REPORT} not generated (earlier stage failed or was skipped)"
        }
      }
    }
    success {
      echo '✅ Security validation completed'
    }
    failure {
      echo '❌ Security validation failed'
      script {
        withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
          if (!env.GITHUB_TOKEN?.trim()) {
            echo "⚠️ GitHub token is empty; skipping failure notification."
            return
          }
          sh '''
            set +e
            WORKDIR="${WORKSPACE:-$(pwd)}"
            ISSUE_TITLE="CI Failure: ${JOB_NAME}"
            ensure_label() {
              LABEL_JSON=$(jq -n --arg name "$1" --arg color "$2" '{name:$name,color:$color}')
              curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/labels/$1" >/dev/null 2>&1 && return 0
              curl -fsSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/labels" -d "$LABEL_JSON" >/dev/null 2>&1 || true
            }
            ensure_label "ci" "6a737d"
            ensure_label "jenkins" "5319e7"
            ensure_label "failure" "b60205"
            ensure_label "automated" "0e8a16"
            ISSUE_LIST_JSON=$(curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=ci,jenkins,failure,automated&per_page=100" || echo "[]")
            ISSUE_NUMBER=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].number // empty' 2>/dev/null || true)
            if [ -n "${ISSUE_NUMBER}" ]; then
              COMMENT_JSON=$(jq -n --arg job "${JOB_NAME}" --arg build "${BUILD_URL}" --arg commit "${GIT_COMMIT}" '{body:("## Jenkins job failed\n\nJob: " + $job + "\nBuild: " + $build + "\nCommit: " + $commit + "\n\n(Automated update on existing issue.)")}')
              if ! curl -sS -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" -d "$COMMENT_JSON" >/dev/null 2>&1; then echo "⚠️ WARNING: Failed to add comment to failure issue #${ISSUE_NUMBER}"; fi
              exit 0
            fi
            ISSUE_BODY_JSON=$(jq -n --arg title "$ISSUE_TITLE" --arg job "${JOB_NAME}" --arg build "${BUILD_URL}" --arg commit "${GIT_COMMIT}" '{title:$title, body:("## Jenkins job failed\n\nJob: " + $job + "\nBuild: " + $build + "\nCommit: " + $commit + "\n\nPlease check Jenkins logs.\n\n---\n*Automated by Jenkins.*"), labels:["ci","jenkins","failure","automated"]}')
            echo "$ISSUE_BODY_JSON" > "$WORKDIR/issue-body-failure.json"
            if ! curl -sS -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/issues" -d @"$WORKDIR/issue-body-failure.json" >/dev/null 2>&1; then echo "⚠️ WARNING: Failed to create failure issue"; fi
          '''
        }
      }
    }
  }
}
