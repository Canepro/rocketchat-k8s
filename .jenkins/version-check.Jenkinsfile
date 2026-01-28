// Version Check Pipeline for rocketchat-k8s
// This pipeline checks for latest versions of all components and creates PRs/issues for updates.
// Purpose: Automated dependency management with risk-based PR/Issue creation.
pipeline {
  agent {
    kubernetes {
      label 'version-checker'
      defaultContainer 'version-checker'
      yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: version-checker
    image: alpine:3.20
    command: ['sleep', '3600']
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "250m"
"""
    }
  }
  
  environment {
    GITHUB_REPO = 'Canepro/rocketchat-k8s'
    GITHUB_TOKEN_CREDENTIALS = 'github-token'
    VERSIONS_FILE = 'VERSIONS.md'
    UPDATE_REPORT = 'version-updates.json'
  }
  
  stages {
    // Stage 1: Install Tools
    stage('Install Tools') {
      steps {
        sh '''
          # Alpine-based agent: install tools via apk
          apk add --no-cache curl jq git bash python3 py3-pip wget yq github-cli || \
            apk add --no-cache curl jq git bash python3 py3-pip wget yq

          # GitHub CLI is optional (pipeline uses curl for API calls); log if missing
          command -v gh >/dev/null 2>&1 && gh --version || echo "gh not installed (ok)"

          # Install yq for YAML parsing (apk 'yq' preferred; fallback binary if missing)
          if ! command -v yq >/dev/null 2>&1; then
            wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            chmod +x /usr/local/bin/yq || true
          fi
        '''
      }
    }
    
    // Stage 2: Check Terraform Provider Versions
    stage('Check Terraform Versions') {
      steps {
        script {
          def terraformVersions = [:]
          
          // Check Azure Provider version
          sh '''
            # Get current version from main.tf
            CURRENT_AZURERM=$(grep -A2 "azurerm = {" terraform/main.tf | grep "version" | sed 's/.*version = "\\(.*\\)".*/\\1/' | tr -d ' ')
            echo "Current Azure Provider: ${CURRENT_AZURERM}"
            
            # Get latest version from Terraform Registry API
            LATEST_AZURERM=$(curl -s https://registry.terraform.io/v1/providers/hashicorp/azurerm/versions | jq -r '.versions[] | .version' | grep -E "^[0-9]+\\.[0-9]+\\.[0-9]+$" | sort -V | tail -1)
            echo "Latest Azure Provider: ${LATEST_AZURERM}"
            
            echo "AZURERM_CURRENT=${CURRENT_AZURERM}" >> versions.env
            echo "AZURERM_LATEST=${LATEST_AZURERM}" >> versions.env
          '''
          
          def azurermCurrent = sh(script: 'grep AZURERM_CURRENT versions.env | cut -d= -f2', returnStdout: true).trim()
          def azurermLatest = sh(script: 'grep AZURERM_LATEST versions.env | cut -d= -f2', returnStdout: true).trim()
          
          terraformVersions['azurerm'] = [
            current: azurermCurrent,
            latest: azurermLatest,
            needsUpdate: azurermCurrent != azurermLatest
          ]
          
          writeJSON file: 'terraform-versions.json', json: terraformVersions
        }
      }
    }
    
    // Stage 3: Check Container Image Versions
    stage('Check Container Image Versions') {
      steps {
        script {
          def imageUpdates = []
          
          // Check Rocket.Chat image version (prefer Docker Hub tags; fallback to GitHub releases)
          sh '''
            # Extract current repo + tag from values.yaml
            if command -v yq >/dev/null 2>&1; then
              RC_REPO=$(yq -r '.image.repository // ""' values.yaml 2>/dev/null | sed 's/#.*$//' | xargs || true)
              RC_TAG=$(yq -r '.image.tag // ""' values.yaml 2>/dev/null | sed 's/#.*$//' | xargs || true)
            else
              RC_REPO=$(grep -E '^\\s*repository:' values.yaml | head -1 | sed 's/.*repository:\\s*//' | sed 's/#.*$//' | xargs || true)
              RC_TAG=$(grep -E '^\\s*tag:' values.yaml | head -1 | sed 's/.*tag:\\s*\"\\{0,1\\}\\([^\"#]*\\)\"\\{0,1\\}.*/\\1/' | sed 's/#.*$//' | xargs || true)
            fi
            echo "Current Rocket.Chat image: ${RC_REPO}:${RC_TAG}"
            
            # Latest Rocket.Chat app release (GitHub)
            LATEST_RC_RELEASE=$(curl -s https://api.github.com/repos/RocketChat/Rocket.Chat/releases/latest | jq -r '.tag_name' | sed 's/^v//')
            
            # Latest Rocket.Chat image tag (registry API if possible)
            REGISTRY_HOST=$(echo "${RC_REPO}" | cut -d'/' -f1)
            REPO_PATH=$(echo "${RC_REPO}" | cut -d'/' -f2-)
            
            if echo "${REGISTRY_HOST}" | grep -q '\\.'; then
              # Custom registry (e.g., registry.rocket.chat)
              LATEST_RC_IMAGE=$(curl -s "https://${REGISTRY_HOST}/v2/${REPO_PATH}/tags/list" | jq -r '.tags[]' 2>/dev/null | grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+$' | sort -V | tail -1)
            else
              # Docker Hub (no explicit registry host in repo)
              REPO_PATH="${RC_REPO#docker.io/}"
              LATEST_RC_IMAGE=$(curl -s "https://registry.hub.docker.com/v2/repositories/${REPO_PATH}/tags?page_size=100" | jq -r '.results[].name' 2>/dev/null | grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+$' | sort -V | tail -1)
            fi
            
            echo "RC_REPO=${RC_REPO}" >> versions.env
            echo "RC_CURRENT=${RC_TAG}" >> versions.env
            echo "RC_LATEST_RELEASE=${LATEST_RC_RELEASE}" >> versions.env
            echo "RC_LATEST_IMAGE=${LATEST_RC_IMAGE}" >> versions.env
          '''
          
          def rcCurrent = sh(script: 'grep RC_CURRENT versions.env | cut -d= -f2', returnStdout: true).trim()
          def rcLatestRelease = sh(script: 'grep RC_LATEST_RELEASE versions.env | cut -d= -f2', returnStdout: true).trim()
          def rcLatestImage = sh(script: 'grep RC_LATEST_IMAGE versions.env | cut -d= -f2', returnStdout: true).trim()
          def rcLatest = rcLatestImage ?: rcLatestRelease
          def rcSource = rcLatestImage ? 'docker-hub' : 'github-release'
          
          if (rcLatest && rcCurrent && rcCurrent != rcLatest) {
            imageUpdates.add([
              component: 'Rocket.Chat Application',
              current: rcCurrent,
              latest: rcLatest,
              location: 'values.yaml',
              // Treat major version bumps as breaking changes
              risk: isMajorVersionUpdate(rcCurrent, rcLatest) ? 'CRITICAL' : 'MEDIUM',
              source: rcSource
            ])
          }
          
          // Check other images from ops/manifests/
          sh '''
            # Extract all image tags from manifests
            grep -r "image:" ops/manifests/*.yaml | grep -v "#" | sed 's/.*image: \\(.*\\)/\\1/' | sort -u > image-list.txt
          '''
          
          writeJSON file: 'image-updates.json', json: imageUpdates
        }
      }
    }
    
    // Stage 4: Check Helm Chart Versions
    stage('Check Helm Chart Versions') {
      steps {
        script {
          def chartUpdates = []
          
          // Check Helm chart versions for all ArgoCD apps
          def chartLines = sh(
            script: '''
              set +e
              for app in GrafanaLocal/argocd/applications/*.yaml; do
                if command -v yq >/dev/null 2>&1; then
                  yq -r '.spec.sources // [ .spec.source ] | .[] | select(has("chart")) | [.chart, .repoURL, (.targetRevision|tostring)] | @tsv' "$app" 2>/dev/null | \
                  while IFS=$'\\t' read -r chart repo current; do
                    [ -z "$chart" ] && continue
                    INDEX_URL="${repo%/}/index.yaml"
                    TMP_INDEX=$(mktemp)
                    if curl -fsSL "$INDEX_URL" -o "$TMP_INDEX"; then
                      latest=$(yq -r ".entries.\"${chart}\"[].version" "$TMP_INDEX" | sort -V | tail -1)
                    else
                      latest=""
                    fi
                    rm -f "$TMP_INDEX"
                    if [ -n "$latest" ] && [ "$latest" != "null" ]; then
                      echo "${app}|${chart}|${current}|${latest}|${repo}"
                    fi
                  done || true
                fi
              done
              true
            ''',
            returnStdout: true
          ).trim()

          if (chartLines) {
            def chartComponentMap = [
              'rocketchat': 'Rocket.Chat Helm Chart',
              'traefik': 'Traefik Helm Chart',
              'jenkins': 'Jenkins Helm Chart',
              'mongodb-kubernetes': 'MongoDB Operator Helm Chart',
              'external-secrets': 'External Secrets Operator Helm Chart'
            ]

            chartLines.split('\\n').each { line ->
              def parts = line.split('\\|')
              if (parts.size() >= 4) {
                def appFile = parts[0].trim()
                def chart = parts[1].trim()
                def current = parts[2].trim()
                def latest = parts[3].trim()
                def componentName = chartComponentMap.get(chart, "Helm Chart: ${chart}")

                if (current && latest && current != latest) {
                  chartUpdates.add([
                    component: componentName,
                    current: current,
                    latest: latest,
                    location: appFile,
                    chart: chart,
                    // Treat major chart bumps as breaking changes
                    risk: isMajorVersionUpdate(current, latest) ? 'CRITICAL' : 'MEDIUM'
                  ])
                }
              }
            }
          }

          writeJSON file: 'chart-updates.json', json: chartUpdates
        }
      }
    }
    
    // Stage 5: Assess Update Risk and Create PR/Issue
    stage('Create Update PRs/Issues') {
      steps {
        script {
          // Aggregate all updates
          def allUpdates = [:]
          def terraformVersions = readJSON file: 'terraform-versions.json'
          def imageUpdates = readJSON file: 'image-updates.json'
          def chartUpdates = readJSON file: 'chart-updates.json'
          
          allUpdates['terraform'] = terraformVersions
          allUpdates['images'] = imageUpdates
          allUpdates['charts'] = chartUpdates
          
          // Categorize by risk
          def criticalUpdates = []
          def highRiskUpdates = []
          def mediumRiskUpdates = []
          
          imageUpdates.each { update ->
            if (update.risk == 'CRITICAL') {
              criticalUpdates.add(update)
            } else if (update.risk == 'HIGH') {
              highRiskUpdates.add(update)
            } else {
              mediumRiskUpdates.add(update)
            }
          }

          chartUpdates.each { update ->
            if (update.risk == 'CRITICAL') {
              criticalUpdates.add(update)
            } else if (update.risk == 'HIGH') {
              highRiskUpdates.add(update)
            } else {
              mediumRiskUpdates.add(update)
            }
          }
          
          // Create report
          def updateReport = [
            timestamp: sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim(),
            critical: criticalUpdates.size(),
            high: highRiskUpdates.size(),
            medium: mediumRiskUpdates.size(),
            updates: allUpdates
          ]
          
          writeJSON file: "${env.UPDATE_REPORT}", json: updateReport
          
          // Create PR or Issue based on risk
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (!env.GITHUB_TOKEN?.trim()) {
              echo "⚠️ GitHub token is empty; skipping issue/PR creation."
              return
            }
            if (criticalUpdates.size() > 0) {
              // Create Issue for breaking (major) updates
              echo "🚨 Creating GitHub issue for BREAKING version updates..."
              def criticalSummary = criticalUpdates.collect { "- ${it.component}: ${it.current} → ${it.latest}" }.join('\\n')
              withEnv(["CRITICAL_UPDATES=${criticalSummary}"]) {
                sh '''
                  ensure_label() {
                    LABEL_NAME="$1"
                    LABEL_COLOR="$2"
                    LABEL_JSON=$(jq -n --arg name "$LABEL_NAME" --arg color "$LABEL_COLOR" '{name:$name,color:$color}')
                    curl -fsSL \
                      -H "Authorization: token ${GITHUB_TOKEN}" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "https://api.github.com/repos/${GITHUB_REPO}/labels/${LABEL_NAME}" >/dev/null 2>&1 && return 0
                    curl -fsSL -X POST \
                      -H "Authorization: token ${GITHUB_TOKEN}" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "https://api.github.com/repos/${GITHUB_REPO}/labels" \
                      -d "$LABEL_JSON" >/dev/null 2>&1 || true
                  }
                  
                  ensure_label "dependencies" "0366d6"
                  ensure_label "breaking" "b60205"
                  ensure_label "automated" "0e8a16"
                  ensure_label "upgrade" "fbca04"
                  
                  cat > issue-body.json << 'ISSUE_EOF'
                  {
                    "title": "🚨 Breaking: Major version updates available",
                    "body": "## Version Update Alert\\n\\n**Risk Level:** BREAKING (major version)\\n\\n**Updates Available:**\\n${CRITICAL_UPDATES}\\n\\n## Action Required\\n\\nMajor version updates detected. These are likely breaking changes and require careful testing before deployment.\\n\\n## Next Steps\\n\\n1. Review breaking changes in release notes\\n2. Test in staging environment\\n3. Create upgrade plan\\n4. Schedule maintenance window if needed\\n\\n---\\n*This issue was automatically created by Jenkins version check pipeline.*",
                    "labels": ["dependencies", "breaking", "automated", "upgrade"]
                  }
ISSUE_EOF
                  
                  curl -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues" \
                    -d @issue-body.json
                '''
              }
            } else if (highRiskUpdates.size() > 0 || mediumRiskUpdates.size() > 0) {
              // Create PR for high/medium risk updates
              echo "⚠️ Creating PR for version updates..."
              
              // Write updates to JSON for shell script processing
              def updatesToApply = [
                high: highRiskUpdates,
                medium: mediumRiskUpdates,
                terraform: terraformVersions
              ]
              writeJSON file: 'updates-to-apply.json', json: updatesToApply
              
              sh '''
                BRANCH_NAME="chore/version-updates-$(date +%Y%m%d)"
                git config user.name "Jenkins Version Bot"
                git config user.email "jenkins@canepro.me"
                git checkout -b ${BRANCH_NAME}
                
                # Process updates and apply to VERSIONS.md and code files
                echo "Applying version updates to files..."
                
                # Update images/charts/providers from high/medium risk updates
                jq -r '.high[] + .medium[] | select(.component != null) | "\\(.component)|\\(.current)|\\(.latest)|\\(.location)|\\(.chart // \"\")"' updates-to-apply.json 2>/dev/null | while IFS='|' read -r component current latest location chart; do
                  if [ -n "$component" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
                    echo "Updating $component: $current → $latest in $location"
                    
                    # Update VERSIONS.md (handle different table formats)
                    # Avoid backtick-escaping (Groovy+shell) by not matching/printing backticks.
                    # Replace the component row's version cell(s) using a loose table-cell match.
                    sed -i "s/| \\*\\*${component}\\*\\* | [^|]* |/| **${component}** | ${latest} |/g" VERSIONS.md || true
                    sed -i "s/| \\*\\*${component}\\*\\* | [^|]* | [^|]* |.*⚠️/| **${component}** | ${latest} | ${latest} | ✅ **Up to date**/g" VERSIONS.md || true
                    
                    # Update actual code files
                    if [ -f "$location" ]; then
                      case "$location" in
                        values.yaml)
                          sed -i "s/tag: \"${current}\"/tag: \"${latest}\"/g" "$location" || true
                          ;;
                        terraform/main.tf)
                          sed -i "s/version = \"~> ${current}\"/version = \"~> ${latest}\"/g" "$location" || true
                          ;;
                        GrafanaLocal/argocd/applications/*.yaml)
                          if command -v yq >/dev/null 2>&1 && [ -n "$chart" ]; then
                            yq -i '
                              if .spec.sources then
                                .spec.sources |= map( if (.chart // "") == "'"$chart"'" then .targetRevision = "'"$latest"'" else . end )
                              else
                                if (.spec.source.chart // "") == "'"$chart"'" then .spec.source.targetRevision = "'"$latest"'" else . end
                              end
                            ' "$location" || true
                          else
                            sed -i "s/targetRevision: ${current}/targetRevision: ${latest}/g" "$location" || true
                          fi
                          # Keep values.yaml chart comment in sync for Rocket.Chat
                          if [ "$chart" = "rocketchat" ]; then
                            sed -i "s/Chart: rocketchat\\/rocketchat ${current}/Chart: rocketchat\\/rocketchat ${latest}/g" values.yaml || true
                          fi
                          ;;
                        ops/manifests/*.yaml)
                          sed -i "s/:${current}/:${latest}/g" "$location" || true
                          ;;
                      esac
                    fi
                  fi
                done
                
                # Update Terraform provider if needed
                if [ "$(jq -r '.terraform.azurerm.needsUpdate // false' updates-to-apply.json 2>/dev/null)" = "true" ]; then
                  CURRENT_TF=$(jq -r '.terraform.azurerm.current' updates-to-apply.json 2>/dev/null | sed 's/~>//' | tr -d ' ')
                  LATEST_TF=$(jq -r '.terraform.azurerm.latest' updates-to-apply.json 2>/dev/null)
                  if [ -n "$CURRENT_TF" ] && [ -n "$LATEST_TF" ] && [ "$CURRENT_TF" != "$LATEST_TF" ]; then
                    echo "Updating Terraform Azure Provider: $CURRENT_TF → $LATEST_TF"
                    sed -i "s/| \\*\\*Azure Provider\\*\\* | [^|]* |/| **Azure Provider** | ~> ${LATEST_TF} |/g" VERSIONS.md || true
                    sed -i "s/version = \"~> ${CURRENT_TF}\"/version = \"~> ${LATEST_TF}\"/g" terraform/main.tf || true
                  fi
                fi
                
                # Create update summary
                HIGH_COUNT=$(jq '.high | length' updates-to-apply.json 2>/dev/null || echo "0")
                MEDIUM_COUNT=$(jq '.medium | length' updates-to-apply.json 2>/dev/null || echo "0")
                
                cat > VERSION_UPDATES.md << EOF
                # Version Updates
                
                This PR includes automated version updates detected by Jenkins.
                
                ## Updates Summary
                - High Risk: ${HIGH_COUNT}
                - Medium Risk: ${MEDIUM_COUNT}
                
                ## Files Updated
                - **VERSIONS.md**: Version tracking automatically updated
                - **Code files**: Actual version numbers updated (values.yaml, terraform/main.tf, etc.)
                
                ## Review Checklist
                - [ ] Review all version changes in VERSIONS.md
                - [ ] Verify code file changes are correct
                - [ ] Check release notes for breaking changes
                - [ ] Test in staging if applicable
EOF
                
                # Stage all changes
                git add VERSIONS.md VERSION_UPDATES.md values.yaml terraform/main.tf ops/manifests/*.yaml 2>/dev/null || true
                
                # Commit with detailed message
                git commit -m "chore: automated version updates

                - High risk: ${HIGH_COUNT}
                - Medium risk: ${MEDIUM_COUNT}
                - Updated VERSIONS.md automatically
                - Updated code files with new versions
                - Generated by Jenkins version check pipeline" || echo "No changes to commit"
                
                # Ensure authenticated remote for push
                set +x
                git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" 2>/dev/null || true
                set -x

                git push origin ${BRANCH_NAME}

                ensure_label() {
                  LABEL_NAME="$1"
                  LABEL_COLOR="$2"
                  LABEL_JSON=$(jq -n --arg name "$LABEL_NAME" --arg color "$LABEL_COLOR" '{name:$name,color:$color}')
                  curl -fsSL \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/labels/${LABEL_NAME}" >/dev/null 2>&1 && return 0
                  curl -fsSL -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/labels" \
                    -d "$LABEL_JSON" >/dev/null 2>&1 || true
                }
                
                ensure_label "dependencies" "0366d6"
                ensure_label "automated" "0e8a16"
                ensure_label "upgrade" "fbca04"
                
                # Create PR
                cat > pr-body.json << EOF
                {
                  "title": "⬆️ Version Updates: ${HIGH_COUNT} high, ${MEDIUM_COUNT} medium",
                  "head": "${BRANCH_NAME}",
                  "base": "master",
                  "body": "## Automated Version Updates\\n\\nThis PR includes version updates detected by automated checks.\\n\\n### Updates Summary\\n- High Risk: ${HIGH_COUNT}\\n- Medium Risk: ${MEDIUM_COUNT}\\n\\n### Files Updated\\n- **VERSIONS.md**: Automatically updated with new versions\\n- **Code files**: Version numbers updated in values.yaml, terraform/main.tf, etc.\\n\\n### Review Required\\n\\nPlease review all changes and test before merging.\\n\\n---\\n*This PR was automatically created by Jenkins version check pipeline.*"
                }
EOF
                
                PR_CREATE_JSON=$(curl -sS -X POST \\
                  -H "Authorization: token ${GITHUB_TOKEN}" \\
                  -H "Accept: application/vnd.github.v3+json" \\
                  "https://api.github.com/repos/${GITHUB_REPO}/pulls" \\
                  -d @pr-body.json || echo '{}')
                
                PR_CREATED_NUMBER=$(echo "$PR_CREATE_JSON" | jq -r '.number // empty' 2>/dev/null || true)
                if [ -n "${PR_CREATED_NUMBER}" ]; then
                  curl -sS -X POST \\
                    -H "Authorization: token ${GITHUB_TOKEN}" \\
                    -H "Accept: application/vnd.github.v3+json" \\
                    "https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_CREATED_NUMBER}/labels" \\
                    -d '{"labels":["dependencies","automated","upgrade"]}' >/dev/null 2>&1 || true
                fi
              '''
            } else {
              echo "✅ All versions are up to date or updates are low risk"
            }
          }
        }
      }
    }
  }
  
  post {
    always {
      archiveArtifacts artifacts: '*.json,*.md', allowEmptyArchive: true
    }
    failure {
      echo '❌ Version check failed'
      script {
        withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
          if (!env.GITHUB_TOKEN?.trim()) {
            echo "⚠️ GitHub token is empty; skipping failure notification."
            return
          }
          sh '''
            set +e
            ISSUE_TITLE="CI Failure: ${JOB_NAME}"
            
            ensure_label() {
              LABEL_NAME="$1"
              LABEL_COLOR="$2"
              LABEL_JSON=$(jq -n --arg name "$LABEL_NAME" --arg color "$LABEL_COLOR" '{name:$name,color:$color}')
              curl -fsSL \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/labels/${LABEL_NAME}" >/dev/null 2>&1 && return 0
              curl -fsSL -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/labels" \
                -d "$LABEL_JSON" >/dev/null 2>&1 || true
            }
            
            ensure_label "ci" "6a737d"
            ensure_label "jenkins" "5319e7"
            ensure_label "failure" "b60205"
            ensure_label "automated" "0e8a16"
            
            ISSUE_LIST_JSON=$(curl -fsSL \
              -H "Authorization: token ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=ci,jenkins,failure,automated&per_page=100" \
              || echo '[]')
            
            ISSUE_NUMBER=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].number // empty' 2>/dev/null || true)
            ISSUE_URL=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].html_url // empty' 2>/dev/null || true)
            
            if [ -n "${ISSUE_NUMBER}" ]; then
              cat > issue-comment.json << EOF
            {
              "body": "## Jenkins job failed\\n\\nJob: ${JOB_NAME}\\nBuild: ${BUILD_URL}\\nCommit: ${GIT_COMMIT}\\n\\n(Automated update on existing issue.)"
            }
EOF
              curl -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" \
                -d @issue-comment.json >/dev/null 2>&1 || true
              echo "Updated existing failure issue: ${ISSUE_URL}"
              exit 0
            fi
            
            cat > issue-body.json << EOF
            {
              "title": "${ISSUE_TITLE}",
              "body": "## Jenkins job failed\\n\\nJob: ${JOB_NAME}\\nBuild: ${BUILD_URL}\\nCommit: ${GIT_COMMIT}\\n\\nPlease check Jenkins logs for details.\\n\\n---\\n*This issue was automatically created by Jenkins.*",
              "labels": ["ci", "jenkins", "failure", "automated"]
            }
EOF
            
            curl -X POST \
              -H "Authorization: token ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/${GITHUB_REPO}/issues" \
              -d @issue-body.json >/dev/null 2>&1 || true
          '''
        }
      }
    }
  }
}

// Helper function to determine if version update is major
def isMajorVersionUpdate(current, latest) {
  def currentMajor = current.split('\\.')[0].toInteger()
  def latestMajor = latest.split('\\.')[0].toInteger()
  return latestMajor > currentMajor
}
