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
    // Stage 1: Install Security Scanning Tools (all tools to WORKDIR so no root needed; supports Alpine, Debian, RHEL/Mariner)
    stage('Install Security Tools') {
      steps {
        sh '''
          set -e
          WORKDIR="${WORKSPACE:-$(pwd)}"
          export WORKDIR
          export PATH="${WORKDIR}/checkov-venv/bin:${WORKDIR}:${PATH}"
          cd "$WORKDIR"

          # Base tools: try package managers
          if command -v apk >/dev/null 2>&1; then
            apk add --no-cache bash ca-certificates curl git jq python3 py3-pip tar wget gzip coreutils 2>/dev/null || true
          elif command -v apt-get >/dev/null 2>&1; then
            (apt-get update -qq && apt-get install -y bash curl git jq python3 python3-pip python3-venv tar wget gzip coreutils) 2>/dev/null || true
          elif command -v yum >/dev/null 2>&1; then
            yum install -y bash curl git jq python3 tar wget gzip coreutils 2>/dev/null || true
          elif command -v tdnf >/dev/null 2>&1; then
            tdnf install -y bash curl git jq python3 tar wget gzip coreutils 2>/dev/null || true
          fi
          update-ca-certificates 2>/dev/null || true

          # jq: if still missing, download to WORKDIR
          if ! command -v jq >/dev/null 2>&1; then
            curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" -o "$WORKDIR/jq"
            chmod +x "$WORKDIR/jq"
          fi

          # tfsec - pinned version, checksum verified, install to WORKDIR
          TFSEC_VERSION="v1.28.14"
          curl -fsSL -o /tmp/tfsec-linux-amd64 "https://github.com/aquasecurity/tfsec/releases/download/${TFSEC_VERSION}/tfsec-linux-amd64"
          curl -fsSL -o /tmp/tfsec_checksums.txt "https://github.com/aquasecurity/tfsec/releases/download/${TFSEC_VERSION}/tfsec_checksums.txt"
          (cd /tmp && grep "tfsec-linux-amd64" tfsec_checksums.txt | grep -v checkgen | sha256sum -c -)
          chmod +x /tmp/tfsec-linux-amd64 && mv /tmp/tfsec-linux-amd64 "$WORKDIR/tfsec"
          rm -f /tmp/tfsec_checksums.txt

          # checkov - pinned version, venv in WORKDIR (fallback to user install)
          CHECKOV_VERSION="3.2.499"
          python3 -m venv "$WORKDIR/checkov-venv" 2>/dev/null || true
          if [ -f "$WORKDIR/checkov-venv/bin/activate" ]; then
            . "$WORKDIR/checkov-venv/bin/activate"
            pip install --quiet --no-cache-dir "checkov==${CHECKOV_VERSION}" || true
            deactivate || true
          elif command -v python3 >/dev/null 2>&1; then
            python3 -m pip install --quiet --no-cache-dir --user "checkov==${CHECKOV_VERSION}" || true
          fi

          # Ensure user-level bin is on PATH for checkov fallback
          if [ -d "${HOME:-/tmp}/.local/bin" ]; then
            export PATH="${HOME:-/tmp}/.local/bin:${PATH}"
          fi

          # trivy - pinned version, checksum verified, install to WORKDIR
          TRIVY_VERSION="0.54.0"
          TRIVY_TGZ="/tmp/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
          curl -fsSL -o "${TRIVY_TGZ}" "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
          curl -fsSL -o /tmp/trivy_checksums.txt "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_checksums.txt"
          (cd /tmp && grep "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" trivy_checksums.txt | sha256sum -c -)
          tar -xzf "${TRIVY_TGZ}" -C /tmp
          mv /tmp/trivy "$WORKDIR/trivy" 2>/dev/null || mv /tmp/trivy_${TRIVY_VERSION}_Linux-64bit/trivy "$WORKDIR/trivy"
          chmod +x "$WORKDIR/trivy"
          rm -f "${TRIVY_TGZ}" /tmp/trivy_checksums.txt
          rm -rf /tmp/trivy_${TRIVY_VERSION}_Linux-64bit 2>/dev/null || true

          # kube-score - pinned version, checksum verified, install to WORKDIR
          KUBE_SCORE_VERSION="1.20.0"
          if command -v apk >/dev/null 2>&1; then apk add --no-cache kube-score 2>/dev/null || true; fi
          if ! command -v kube-score >/dev/null 2>&1; then
            curl -fsSL -o /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VERSION}/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz"
            curl -fsSL -o /tmp/kube-score_checksums.txt "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VERSION}/checksums.txt"
            (cd /tmp && grep "kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz" kube-score_checksums.txt | sha256sum -c -)
            tar -xzf /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz -C /tmp
            mv /tmp/kube-score "$WORKDIR/kube-score" 2>/dev/null || mv /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64/kube-score "$WORKDIR/kube-score"
            chmod +x "$WORKDIR/kube-score"
            rm -f /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz /tmp/kube-score_checksums.txt
            rm -rf /tmp/kube-score_${KUBE_SCORE_VERSION}_linux_amd64 2>/dev/null || true
          fi

          tfsec --version || echo "tfsec not installed"
          checkov --version || echo "checkov not installed"
          trivy --version || echo "trivy not installed"
          kube-score version || echo "kube-score not installed"
          
          # Clean up old scan results to prevent accumulation across runs
          rm -f "$WORKDIR"/*.json "$WORKDIR"/*.txt "$WORKDIR"/*.md 2>/dev/null || true
        '''
      }
    }
    
    // Stage 2: Terraform Security Scan (tfsec)
    stage('Terraform Security Scan (tfsec)') {
      steps {
        dir('terraform') {
          sh '''
            export PATH="${WORKSPACE}/checkov-venv/bin:${WORKSPACE}:${HOME:-/tmp}/.local/bin:${PATH}"
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
            export PATH="${WORKSPACE}/checkov-venv/bin:${WORKSPACE}:${HOME:-/tmp}/.local/bin:${PATH}"
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
          export PATH="${WORKSPACE}/checkov-venv/bin:${WORKSPACE}:${PATH}"
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
            writeFile file: 'trivy-images.txt', text: "${images}\n"
            
            // Scan each image
            images.split('\n').each { line ->
              if (line.contains(':')) {
                def image = line.trim()
                sh """
                  export PATH="\${WORKSPACE}/checkov-venv/bin:\${WORKSPACE}:\${PATH}"
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
          // Use jq so we don't depend on pipeline-utility-steps or script approvals.
          sh '''
            set -e
            WORKDIR="${WORKSPACE:-$(pwd)}"
            export PATH="${WORKDIR}/checkov-venv/bin:${WORKDIR}:${HOME:-/tmp}/.local/bin:${PATH}"

            tfsec_critical=0; tfsec_high=0; tfsec_medium=0; tfsec_low=0
            checkov_critical=0; checkov_high=0; checkov_medium=0; checkov_low=0

            if [ -f "${TFSEC_OUTPUT}" ]; then
              tfsec_critical=$(jq '[.results[]? | select(.severity=="CRITICAL")] | length' "${TFSEC_OUTPUT}" 2>/dev/null || echo 0)
              tfsec_high=$(jq '[.results[]? | select(.severity=="HIGH")] | length' "${TFSEC_OUTPUT}" 2>/dev/null || echo 0)
              tfsec_medium=$(jq '[.results[]? | select(.severity=="MEDIUM")] | length' "${TFSEC_OUTPUT}" 2>/dev/null || echo 0)
              tfsec_low=$(jq '[.results[]? | select(.severity=="LOW")] | length' "${TFSEC_OUTPUT}" 2>/dev/null || echo 0)
            fi

            if [ -f "${CHECKOV_OUTPUT}" ]; then
              read -r checkov_critical checkov_high checkov_medium checkov_low <<EOF || true
            $(jq -r '
              def failed:
                if type=="object" then
                  if .results? and (.results.check_results? | type=="array") then [.results.check_results[] | select(.check_result.result=="FAILED")]
                  elif .results? and (.results.failed_checks? | type=="array") then .results.failed_checks
                  elif .failed_checks? then .failed_checks
                  else [] end
                elif type=="array" then
                  [ .[] | if .results? and (.results.failed_checks? | type=="array") then .results.failed_checks[] elif .results? and (.results.check_results? | type=="array") then .results.check_results[] | select(.check_result.result=="FAILED") else empty end ]
                else [] end;
              def sev(v): (v.check_result.severity // v.severity // "MEDIUM") | ascii_upcase;
              def count(s): failed | map(sev(.)) | map(select(.==s)) | length;
              [count("CRITICAL"), count("HIGH"), count("MEDIUM"), count("LOW")] | @tsv
            ' "${CHECKOV_OUTPUT}" 2>/dev/null || echo "0 0 0 0")
EOF
            fi

            critical=$((tfsec_critical + checkov_critical))
            high=$((tfsec_high + checkov_high))
            medium=$((tfsec_medium + checkov_medium))
            low=$((tfsec_low + checkov_low))

            if [ "$critical" -gt 0 ]; then
              risk_level="CRITICAL"
            elif [ "$high" -gt 0 ]; then
              risk_level="HIGH"
            elif [ "$medium" -gt 0 ]; then
              risk_level="MEDIUM"
            else
              risk_level="LOW"
            fi

            if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ] || [ "$medium" -gt 0 ]; then
              action_required=true
            else
              action_required=false
            fi

            timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            jq -n \
              --arg ts "$timestamp" \
              --arg risk "$risk_level" \
              --argjson critical "$critical" \
              --argjson high "$high" \
              --argjson medium "$medium" \
              --argjson low "$low" \
              --argjson action "$action_required" \
              '{timestamp:$ts,critical:$critical,high:$high,medium:$medium,low:$low,risk_level:$risk,action_required:$action}' \
              > "${RISK_REPORT}"
            echo "Risk Assessment: $(cat "${RISK_REPORT}")"
          '''

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
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (!env.GITHUB_TOKEN?.trim()) {
              echo "⚠️ GitHub token is empty; skipping."
              return
            }
            withEnv(["GITHUB_REPO=${env.GITHUB_REPO}"]) {
              sh '''
                set -e
                WORKDIR="${WORKSPACE:-$(pwd)}"
                export PATH="${WORKDIR}/checkov-venv/bin:${WORKDIR}:${HOME:-/tmp}/.local/bin:${PATH}"
                ISSUE_TITLE="Security: Critical vulnerabilities detected (automated)"

                RISK_LEVEL=$(jq -r '.risk_level' "${RISK_REPORT}")
                CRITICAL_COUNT=$(jq -r '.critical' "${RISK_REPORT}")
                HIGH_COUNT=$(jq -r '.high' "${RISK_REPORT}")
                MEDIUM_COUNT=$(jq -r '.medium' "${RISK_REPORT}")
                LOW_COUNT=$(jq -r '.low' "${RISK_REPORT}")
                ACTION_REQUIRED=$(jq -r '.action_required' "${RISK_REPORT}")
                if [ "${ACTION_REQUIRED}" != "true" ]; then
                  echo "✅ No remediation needed (risk_level=${RISK_LEVEL})."
                  exit 0
                fi

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

                RUN_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                BRANCH="${GIT_BRANCH:-${BRANCH_NAME:-unknown}}"
                SHORT_COMMIT="${GIT_COMMIT:-unknown}"
                SHORT_COMMIT=$(printf "%s" "$SHORT_COMMIT" | cut -c1-7)
                ARTIFACT_BASE=""
                if [ -n "${BUILD_URL:-}" ]; then
                  ARTIFACT_BASE="${BUILD_URL}artifact/"
                fi

                tfsec_summary="n/a"
                if [ -f "${TFSEC_OUTPUT}" ]; then
                  tfsec_c=$(jq '[.results[]? | select(.severity=="CRITICAL")] | length' "${TFSEC_OUTPUT}" 2>/dev/null || echo 0)
                  tfsec_h=$(jq '[.results[]? | select(.severity=="HIGH")] | length' "${TFSEC_OUTPUT}" 2>/dev/null || echo 0)
                  tfsec_m=$(jq '[.results[]? | select(.severity=="MEDIUM")] | length' "${TFSEC_OUTPUT}" 2>/dev/null || echo 0)
                  tfsec_l=$(jq '[.results[]? | select(.severity=="LOW")] | length' "${TFSEC_OUTPUT}" 2>/dev/null || echo 0)
                  tfsec_summary="C:${tfsec_c} H:${tfsec_h} M:${tfsec_m} L:${tfsec_l}"
                fi

                checkov_summary="n/a"
                if [ -f "${CHECKOV_OUTPUT}" ]; then
                  checkov_total=$(jq '.results.failed_checks | length' "${CHECKOV_OUTPUT}" 2>/dev/null || echo 0)
                  if jq -e '.results.failed_checks[]? | has("severity")' "${CHECKOV_OUTPUT}" >/dev/null 2>&1; then
                    checkov_c=$(jq '[.results.failed_checks[]? | select(.severity=="CRITICAL")] | length' "${CHECKOV_OUTPUT}" 2>/dev/null || echo 0)
                    checkov_h=$(jq '[.results.failed_checks[]? | select(.severity=="HIGH")] | length' "${CHECKOV_OUTPUT}" 2>/dev/null || echo 0)
                    checkov_m=$(jq '[.results.failed_checks[]? | select(.severity=="MEDIUM")] | length' "${CHECKOV_OUTPUT}" 2>/dev/null || echo 0)
                    checkov_l=$(jq '[.results.failed_checks[]? | select(.severity=="LOW")] | length' "${CHECKOV_OUTPUT}" 2>/dev/null || echo 0)
                    checkov_summary="C:${checkov_c} H:${checkov_h} M:${checkov_m} L:${checkov_l} (total:${checkov_total})"
                  else
                    checkov_summary="failed_checks:${checkov_total}"
                  fi
                fi

                kube_score_summary="n/a"
                if [ -f "$WORKDIR/kube-score-results.json" ]; then
                  ks_c=$(jq '[.[]? | .checks[]? | select(.grade=="critical")] | length' "$WORKDIR/kube-score-results.json" 2>/dev/null || echo 0)
                  ks_w=$(jq '[.[]? | .checks[]? | select(.grade=="warning")] | length' "$WORKDIR/kube-score-results.json" 2>/dev/null || echo 0)
                  kube_score_summary="critical:${ks_c} warning:${ks_w}"
                fi

                helm_kube_score_summary="n/a"
                if [ -f "$WORKDIR/helm-kube-score-results.json" ]; then
                  hks_c=$(jq '[.[]? | .checks[]? | select(.grade=="critical")] | length' "$WORKDIR/helm-kube-score-results.json" 2>/dev/null || echo 0)
                  hks_w=$(jq '[.[]? | .checks[]? | select(.grade=="warning")] | length' "$WORKDIR/helm-kube-score-results.json" 2>/dev/null || echo 0)
                  helm_kube_score_summary="critical:${hks_c} warning:${hks_w}"
                fi

                trivy_summary="n/a"
                trivy_files=$(ls "$WORKDIR"/trivy-*.json 2>/dev/null || true)
                if [ -n "$trivy_files" ]; then
                  trivy_c=0; trivy_h=0; trivy_m=0; trivy_l=0
                  for f in $trivy_files; do
                    read -r c h m l <<EOF || true
$(jq -r 'def count(sev): ([.Results[]?.Vulnerabilities[]? | select(.Severity==sev)] | length); [count("CRITICAL"),count("HIGH"),count("MEDIUM"),count("LOW")] | @tsv' "$f" 2>/dev/null || echo "0 0 0 0")
EOF
                    trivy_c=$((trivy_c + c))
                    trivy_h=$((trivy_h + h))
                    trivy_m=$((trivy_m + m))
                    trivy_l=$((trivy_l + l))
                  done
                  trivy_summary="C:${trivy_c} H:${trivy_h} M:${trivy_m} L:${trivy_l}"
                fi

                images_block="(none)"
                if [ -s "$WORKDIR/trivy-images.txt" ]; then
                  images_block=$(sed 's/^/- /' "$WORKDIR/trivy-images.txt")
                fi

                artifact_lines=""
                if [ -n "$ARTIFACT_BASE" ]; then
                  artifact_lines="- tfsec results: ${ARTIFACT_BASE}${TFSEC_OUTPUT}
- checkov results: ${ARTIFACT_BASE}${CHECKOV_OUTPUT}
- trivy results: ${ARTIFACT_BASE}trivy-*.json"
                else
                  artifact_lines="- tfsec results: See Jenkins build artifacts
- checkov results: See Jenkins build artifacts
- trivy results: See Jenkins build artifacts"
                fi

                COMMENT_MARKDOWN=$(cat <<EOF
## New security scan results

- **Build:** ${BUILD_URL}
- **Findings:** Critical: ${CRITICAL_COUNT} | High: ${HIGH_COUNT} | Medium: ${MEDIUM_COUNT} | Low: ${LOW_COUNT}
- **Artifacts:** ${ARTIFACT_BASE:-See Jenkins build artifacts}

(De-dupe enabled: this comment updates an existing open issue.)
EOF
)

                COMMENT_BODY=$(jq -n --arg body "$COMMENT_MARKDOWN" '{body:$body}')
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

                ISSUE_MARKDOWN=$(cat <<EOF
## Security Scan Results

- **Risk Level:** ${RISK_LEVEL}
- **Findings:**
  - Critical: ${CRITICAL_COUNT}
  - High: ${HIGH_COUNT}
  - Medium: ${MEDIUM_COUNT}
  - Low: ${LOW_COUNT}

**Action Required:** Please review the security scan results and address critical vulnerabilities immediately.

**Scan Artifacts:**
${artifact_lines}

**Next Steps:**
1. Review all critical findings
2. Create remediation PRs for each critical issue
3. Update security policies if needed

This issue was automatically created by Jenkins security validation pipeline.
EOF
)
                ISSUE_BODY_JSON=$(jq -n --arg title "$ISSUE_TITLE" --arg body "$ISSUE_MARKDOWN" --arg risk "$RISK_LEVEL" \
                  '{title:$title, body:$body, labels:(["security","automated"] + (if $risk == "CRITICAL" then ["critical"] else [] end))}')
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
          sh '''
            set +e
            WORKDIR="${WORKSPACE:-$(pwd)}"
            export PATH="${WORKDIR}/checkov-venv/bin:${WORKDIR}:${PATH}"
            if ! command -v jq >/dev/null 2>&1; then
              echo "Security Scan Summary: jq not available"
              exit 0
            fi
            CRITICAL=$(jq -r '.critical' "${RISK_REPORT}")
            HIGH=$(jq -r '.high' "${RISK_REPORT}")
            MEDIUM=$(jq -r '.medium' "${RISK_REPORT}")
            LOW=$(jq -r '.low' "${RISK_REPORT}")
            RISK_LEVEL=$(jq -r '.risk_level' "${RISK_REPORT}")
            ACTION_REQUIRED=$(jq -r '.action_required' "${RISK_REPORT}")
            cat <<EOF
========================================
Security Scan Summary
========================================
Critical: ${CRITICAL}
High: ${HIGH}
Medium: ${MEDIUM}
Low: ${LOW}
Risk Level: ${RISK_LEVEL}
Action Required: ${ACTION_REQUIRED}
========================================
EOF
          '''
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
            export PATH="${WORKDIR}/checkov-venv/bin:${WORKDIR}:${PATH}"
            if ! command -v jq >/dev/null 2>&1; then
              curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" -o "$WORKDIR/jq" 2>/dev/null && chmod +x "$WORKDIR/jq" || true
            fi
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

            RUN_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            BRANCH="${GIT_BRANCH:-${BRANCH_NAME:-unknown}}"
            SHORT_COMMIT="${GIT_COMMIT:-unknown}"
            SHORT_COMMIT=$(printf "%s" "$SHORT_COMMIT" | cut -c1-7)

            if [ -n "${ISSUE_NUMBER}" ]; then
              FAIL_COMMENT=$(cat <<EOF
## CI failure update
- Job: ${JOB_NAME}
- Build: ${BUILD_URL}
- Branch: ${BRANCH}
- Commit: ${SHORT_COMMIT}
- Timestamp (UTC): ${RUN_AT}

Please check Jenkins logs for details.
EOF
)
              COMMENT_JSON=$(jq -n --arg body "$FAIL_COMMENT" '{body:$body}')
              if ! curl -sS -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" -d "$COMMENT_JSON" >/dev/null 2>&1; then echo "⚠️ WARNING: Failed to add comment to failure issue #${ISSUE_NUMBER}"; fi
              exit 0
            fi
            FAIL_BODY=$(cat <<EOF
## CI failure
- Job: ${JOB_NAME}
- Build: ${BUILD_URL}
- Branch: ${BRANCH}
- Commit: ${SHORT_COMMIT}
- Timestamp (UTC): ${RUN_AT}

## Next steps
1. Open the Jenkins build logs.
2. Find the first error line.
3. Fix and re-run the job.

## Best practices
1. Capture the first error line in the issue comment.
2. Prefer small, targeted fixes and rerun the job.
3. Avoid re-running without changes.

---
*Automated by Jenkins.*
EOF
)
            ISSUE_BODY_JSON=$(jq -n --arg title "$ISSUE_TITLE" --arg body "$FAIL_BODY" '{title:$title, body:$body, labels:["ci","jenkins","failure","automated"]}')
            echo "$ISSUE_BODY_JSON" > "$WORKDIR/issue-body-failure.json"
            if ! curl -sS -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/issues" -d @"$WORKDIR/issue-body-failure.json" >/dev/null 2>&1; then echo "⚠️ WARNING: Failed to create failure issue"; fi
          '''
        }
      }
    }
  }
}
