import com.cloudbees.groovy.cps.NonCPS

// Version Check Pipeline for rocketchat-k8s
// This pipeline checks for latest versions of all components and creates PRs/issues for updates.
// Purpose: Automated dependency management with risk-based PR/Issue creation.
// Runs on the static AKS agent (aks-agent); AKS has auto-shutdown so controller lives on OKE.
def terraformVersions = [:]
def imageUpdates = []
def chartUpdates = []

pipeline {
  agent { label 'aks-agent' }
  
  environment {
    GITHUB_REPO = 'Canepro/rocketchat-k8s'
    GITHUB_TOKEN_CREDENTIALS = 'github-token'
    VERSIONS_FILE = 'VERSIONS.md'
    UPDATE_REPORT = 'version-updates.json'
  }
  
  stages {
    // Stage 1: Install Tools
    // WORKDIR: use for all manifest updates and curl -d @... so paths work regardless of cwd.
    // Supports Alpine (apk), Debian/Ubuntu (apt), RHEL/Mariner (yum/tdnf). If pkg install fails (e.g. no root), jq/yq/helm are installed into WORKDIR and PATH is set so no root needed.
    // yq: mikefarah/yq (in-place YAML edits); verify download with release checksums.
    // ensure_label: single script created here, sourced in PR/issue and post blocks.
    stage('Install Tools') {
      steps {
        sh '''
          set -e
          WORKDIR="${WORKSPACE:-$(pwd)}"
          export WORKDIR
          cd "$WORKDIR"
          export PATH="${WORKDIR}:${PATH}"

          # Base tools: try package managers (agent may be Alpine, Debian, or RHEL/Mariner)
          if command -v apk >/dev/null 2>&1; then
            apk add --no-cache curl jq git bash python3 py3-pip wget 2>/dev/null || true
            apk add --no-cache github-cli 2>/dev/null || true
          elif command -v apt-get >/dev/null 2>&1; then
            (apt-get update -qq && apt-get install -y curl jq git bash python3 python3-pip wget) 2>/dev/null || true
          elif command -v yum >/dev/null 2>&1; then
            yum install -y curl jq git bash python3 wget 2>/dev/null || true
          elif command -v tdnf >/dev/null 2>&1; then
            tdnf install -y curl jq git bash python3 wget 2>/dev/null || true
          fi

          # jq: if still missing (e.g. no root for apt), download to WORKDIR
          if ! command -v jq >/dev/null 2>&1; then
            JQ_VERSION="jq-1.7.1"
            curl -fsSL "https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-linux-amd64" -o "$WORKDIR/jq"
            chmod +x "$WORKDIR/jq"
          fi

          # mikefarah/yq (required for in-place manifest updates) — install to WORKDIR so no root needed
          YQ_VERSION="v4.35.1"
          YQ_BASE_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}"
          YQ_ASSET="yq_linux_amd64"
          curl -fsSL -o "$WORKDIR/yq" "${YQ_BASE_URL}/${YQ_ASSET}"
          # Try known checksum filenames across releases.
          CHECKSUM_OK=0
          YQ_ACTUAL_SHA=$(sha256sum "$WORKDIR/yq" | awk '{print $1}')
          for YQ_SUM_FILE in checksums_sha256 checksums.txt checksums; do
            if curl -fsSL -o "$WORKDIR/yq_checksums" "${YQ_BASE_URL}/${YQ_SUM_FILE}"; then
              if grep "${YQ_ASSET}" "$WORKDIR/yq_checksums" >/dev/null 2>&1; then
                # Support both "<hash>  filename" and "SHA256 (filename) = <hash>" formats.
                # Match the exact asset name to avoid picking tar.gz or other variants.
                YQ_EXPECTED_SHA=$(grep -E "^[0-9a-fA-F]{64}[[:space:]]+${YQ_ASSET}([[:space:]]|\$)" "$WORKDIR/yq_checksums" | awk '{print $1}' | head -1 || true)
                if [ -z "$YQ_EXPECTED_SHA" ]; then
                  YQ_EXPECTED_SHA=$(grep -E "SHA256 \\(${YQ_ASSET}\\)" "$WORKDIR/yq_checksums" | grep -Eo '[0-9a-fA-F]{64}' | head -1 || true)
                fi
                if [ -n "$YQ_EXPECTED_SHA" ]; then
                  if [ "$YQ_EXPECTED_SHA" = "$YQ_ACTUAL_SHA" ]; then
                    CHECKSUM_OK=1
                    break
                  else
                    echo "WARNING: yq checksum mismatch in ${YQ_SUM_FILE}"
                  fi
                else
                  echo "WARNING: yq checksum format not recognized in ${YQ_SUM_FILE}; skipping verification"
                  CHECKSUM_OK=1
                  break
                fi
              fi
            fi
          done
          rm -f "$WORKDIR/yq_checksums"
          if [ "$CHECKSUM_OK" -ne 1 ]; then
            echo "Failed to verify yq checksum for ${YQ_VERSION}"
            exit 1
          fi
          chmod +x "$WORKDIR/yq"
          yq --version

          # Helm: pin installer; install to WORKDIR so no root needed
          HELM_VERSION="v3.14.0"
          curl -fsSL "https://raw.githubusercontent.com/helm/helm/${HELM_VERSION}/scripts/get-helm-3" -o "$WORKDIR/get-helm-3"
          chmod +x "$WORKDIR/get-helm-3"
          HELM_INSTALL_PREFIX="$WORKDIR" "$WORKDIR/get-helm-3" --no-sudo 2>/dev/null || { echo "⚠️ WARNING: Helm install failed; chart checks may use curl+yq only."; }
          helm version --short 2>/dev/null || true

          # ensure_label.sh: single script for PR/issue/post blocks to source.
          # Note: label names with spaces/special chars would need URL encoding in the API path; current labels (e.g. dependencies, automated) are safe.
          cat > "$WORKDIR/ensure_label.sh" << 'ENSURE_LABEL_EOF'
ensure_label() {
  local LABEL_NAME="$1"
  local LABEL_COLOR="$2"
  local LABEL_JSON
  LABEL_JSON=$(jq -n --arg name "$LABEL_NAME" --arg color "$LABEL_COLOR" '{name:$name,color:$color}')
  if curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/labels/${LABEL_NAME}" >/dev/null 2>&1; then return 0; fi
  if ! curl -fsSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/labels" -d "$LABEL_JSON" >/dev/null 2>&1; then echo "⚠️ WARNING: Failed to create label ${LABEL_NAME}"; fi
}
ENSURE_LABEL_EOF
          chmod +x "$WORKDIR/ensure_label.sh"

          for tool in curl jq git bash yq; do
            if ! command -v "$tool" >/dev/null 2>&1; then
              echo "Critical tool $tool not installed"
              exit 1
            fi
          done
          command -v gh >/dev/null 2>&1 && gh --version || echo "gh not installed (ok)"
        '''
      }
    }
    
    // Stage 2: Check Terraform Provider Versions
    stage('Check Terraform Versions') {
      steps {
        script {
          terraformVersions = [:]
          
          // Check Azure Provider version
          sh '''
            set -e
            WORKDIR="${WORKSPACE:-$(pwd)}"
            export PATH="${WORKDIR}:${PATH}"
            cd "$WORKDIR"
            
            # Clear versions.env to avoid accumulating duplicates across runs
            > "$WORKDIR/versions.env"
            
            if [ ! -f terraform/main.tf ]; then
              echo "terraform/main.tf not found; cannot check Azure provider version."
              exit 1
            fi
            # Get current version from main.tf (may be constraint e.g. ~>3.0). Take first match only to avoid duplicate values.
            CURRENT_AZURERM=$(grep -A2 "azurerm = {" terraform/main.tf | grep "version" | sed 's/.*version = "\\(.*\\)".*/\\1/' | tr -d ' ' | head -1)
            if [ -z "${CURRENT_AZURERM}" ]; then
              echo "Failed to extract current Azure provider version from terraform/main.tf (grep pattern did not match)."
              echo "Please verify the provider \"azurerm\" block and its version field format."
              exit 1
            fi
            echo "Current Azure Provider: ${CURRENT_AZURERM}"
            # Get latest version from Terraform Registry API (plain semver only)
            LATEST_AZURERM=$(curl -sSf https://registry.terraform.io/v1/providers/hashicorp/azurerm/versions | jq -r '.versions[] | .version' | grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+$' | sort -V | tail -1)
            if [ -z "${LATEST_AZURERM}" ]; then
              echo "Failed to retrieve latest Azure provider version from Terraform Registry"
              exit 1
            fi
            echo "Latest Azure Provider: ${LATEST_AZURERM}"
            echo "AZURERM_CURRENT=${CURRENT_AZURERM}" >> "$WORKDIR/versions.env"
            echo "AZURERM_LATEST=${LATEST_AZURERM}" >> "$WORKDIR/versions.env"
          '''
          
          def azurermCurrent = sh(script: 'WORKDIR="${WORKSPACE:-.}"; grep AZURERM_CURRENT "$WORKDIR/versions.env" | head -1 | cut -d= -f2', returnStdout: true).trim()
          def azurermLatest = sh(script: 'WORKDIR="${WORKSPACE:-.}"; grep AZURERM_LATEST "$WORKDIR/versions.env" | head -1 | cut -d= -f2', returnStdout: true).trim()
          
          terraformVersions['azurerm'] = [
            current: azurermCurrent,
            latest: azurermLatest,
            needsUpdate: azurermCurrent != azurermLatest
          ]
          
          writeJsonFile('terraform-versions.json', terraformVersions)
        }
      }
    }
    
    // Stage 3: Check Container Image Versions
    stage('Check Container Image Versions') {
      steps {
        script {
          imageUpdates = []
          
          // Check Rocket.Chat image version (prefer Docker Hub tags; fallback to GitHub releases)
          sh '''
            set -e
            WORKDIR="${WORKSPACE:-$(pwd)}"
            export PATH="${WORKDIR}:${PATH}"
            cd "$WORKDIR"
            # Extract current repo + tag from values.yaml (mikefarah/yq)
            if command -v yq >/dev/null 2>&1; then
              RC_REPO=$(yq -r '.image.repository // ""' "$WORKDIR/values.yaml" 2>/dev/null | sed 's/#.*$//' | xargs || true)
              RC_TAG=$(yq -r '.image.tag // ""' "$WORKDIR/values.yaml" 2>/dev/null | sed 's/#.*$//' | xargs || true)
            else
              RC_REPO=$(grep -E '^\\s*repository:' "$WORKDIR/values.yaml" | head -1 | sed 's/.*repository:\\s*//' | sed 's/#.*$//' | xargs || true)
              RC_TAG=$(grep -E '^\\s*tag:' "$WORKDIR/values.yaml" | head -1 | sed 's/.*tag:\\s*\"\\{0,1\\}\\([^\"#]*\\)\"\\{0,1\\}.*/\\1/' | sed 's/#.*$//' | xargs || true)
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
            
            echo "RC_REPO=${RC_REPO}" >> "$WORKDIR/versions.env"
            echo "RC_CURRENT=${RC_TAG}" >> "$WORKDIR/versions.env"
            echo "RC_LATEST_RELEASE=${LATEST_RC_RELEASE}" >> "$WORKDIR/versions.env"
            echo "RC_LATEST_IMAGE=${LATEST_RC_IMAGE}" >> "$WORKDIR/versions.env"
          '''
          
          def rcCurrent = sh(script: 'WORKDIR="${WORKSPACE:-.}"; grep RC_CURRENT "$WORKDIR/versions.env" | cut -d= -f2', returnStdout: true).trim()
          def rcLatestRelease = sh(script: 'WORKDIR="${WORKSPACE:-.}"; grep RC_LATEST_RELEASE "$WORKDIR/versions.env" | cut -d= -f2', returnStdout: true).trim()
          def rcLatestImage = sh(script: 'WORKDIR="${WORKSPACE:-.}"; grep RC_LATEST_IMAGE "$WORKDIR/versions.env" | cut -d= -f2', returnStdout: true).trim()
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
          
          writeJsonFile('image-updates.json', imageUpdates)
        }
      }
    }
    
    // Stage 4: Check Helm Chart Versions
    stage('Check Helm Chart Versions') {
      steps {
        script {
          chartUpdates = []
          
          // Check Helm chart versions for all ArgoCD apps
          def chartLines = sh(
            script: '''
              set +e
              export PATH="${WORKSPACE}:${PATH}"
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

          writeJsonFile('chart-updates.json', chartUpdates)
        }
      }
    }
    
    // Stage 5: Assess Update Risk and Create PR/Issue
    stage('Create Update PRs/Issues') {
      steps {
        script {
          // Aggregate all updates
          def allUpdates = [:]
          allUpdates['terraform'] = terraformVersions
          allUpdates['images'] = imageUpdates
          allUpdates['charts'] = chartUpdates
          
          // Categorize by risk
          def criticalUpdates = []
          def highRiskUpdates = []
          def mediumRiskUpdates = []
          
          // Classify Terraform provider update risk (so we can avoid auto-PR for breaking bumps)
          if (terraformVersions?.azurerm?.needsUpdate) {
            terraformVersions.azurerm.risk = isMajorVersionUpdate(terraformVersions.azurerm.current, terraformVersions.azurerm.latest) ? 'CRITICAL' : 'MEDIUM'
          } else {
            terraformVersions?.azurerm?.put('risk', 'LOW')
          }

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
          
          // If Terraform provider update is a major bump, treat it as breaking (issue), otherwise allow PR.
          if (terraformVersions?.azurerm?.needsUpdate) {
            def tfRisk = terraformVersions.azurerm.risk
            if (tfRisk == 'CRITICAL') {
              criticalUpdates.add([
                component: 'Terraform Azure Provider (azurerm)',
                current: terraformVersions.azurerm.current,
                latest: terraformVersions.azurerm.latest,
                location: 'terraform/main.tf',
                risk: 'CRITICAL',
                source: 'terraform-registry'
              ])
            } else {
              // Do NOT add terraform to mediumRiskUpdates list (PR script has a dedicated terraform section).
              // We only need terraform risk info in updates-to-apply.json.
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
          
          writeJsonFile("${env.UPDATE_REPORT}", updateReport)
          
          // Create PR or Issue based on risk
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (!env.GITHUB_TOKEN?.trim()) {
              echo "⚠️ GitHub token is empty; skipping issue/PR creation."
              return
            }
            def createdBreakingIssue = false

            if (criticalUpdates.size() > 0) {
              // HIGH→issue: Create Issue for breaking (major) updates (format matches issue #5: bullet list "Component: current → latest")
              echo "🚨 Creating GitHub issue for BREAKING version updates..."
              def criticalBullets = criticalUpdates.collect { update ->
                def cell = { Object v -> (v?.toString() ?: 'n/a').replaceAll(/\r?\n/, ' ').trim() }
                "- ${cell(update.component)}: ${cell(update.current)} → ${cell(update.latest)}"
              }
              writeFile file: 'critical-updates.md', text: criticalBullets.join('\n') + '\n'
              withEnv([]) {
                sh '''
                  set -e
                  WORKDIR="${WORKSPACE:-$(pwd)}"
                  export PATH="${WORKDIR}:${PATH}"
                  cd "$WORKDIR"
                  [ -f "$WORKDIR/ensure_label.sh" ] && . "$WORKDIR/ensure_label.sh" || true
                  ensure_label "dependencies" "0366d6"
                  ensure_label "breaking" "b60205"
                  ensure_label "automated" "0e8a16"
                  ensure_label "upgrade" "fbca04"

                  RUN_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                  BRANCH="${GIT_BRANCH:-${BRANCH_NAME:-unknown}}"
                  SHORT_COMMIT="${GIT_COMMIT:-unknown}"
                  SHORT_COMMIT=$(printf "%s" "$SHORT_COMMIT" | cut -c1-7)
                  ARTIFACT_BASE=""
                  if [ -n "${BUILD_URL:-}" ]; then
                    ARTIFACT_BASE="${BUILD_URL}artifact/"
                  fi
                  UPDATES_BULLETS=$(cat "$WORKDIR/critical-updates.md" | tr -d '\\r')

                  ISSUE_TITLE="Breaking: Major version updates available"
                  ISSUE_BODY=$(jq -rn --arg updates "$UPDATES_BULLETS" '
                    "## Version Update Alert\n\n" +
                    "- **Risk Level:** BREAKING (major version)\n\n" +
                    "**Updates Available:**\n" + $updates + "\n\n" +
                    "**Action Required:** Major version updates detected. These are likely breaking changes and require careful testing before deployment.\n\n" +
                    "**Next Steps:**\n" +
                    "1. Review breaking changes in release notes\n" +
                    "2. Test in staging environment\n" +
                    "3. Create upgrade plan\n" +
                    "4. Schedule maintenance window if needed\n\n" +
                    "This issue was automatically created by Jenkins version check pipeline.\n"
                  ')
                  printf '%s' "$ISSUE_BODY" > "$WORKDIR/issue-body.md"
                  ISSUE_BODY_JSON=$(jq -n \
                    --arg title "$ISSUE_TITLE" \
                    --arg body "$ISSUE_BODY" \
                    '{title:$title, body:$body, labels:["dependencies","breaking","automated","upgrade"]}')
                  printf '%s' "$ISSUE_BODY_JSON" > "$WORKDIR/issue-body.json"
                  ISSUE_LIST_JSON=$(curl -fsSL \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=dependencies,breaking,automated,upgrade&per_page=100" \
                    || echo '[]')
                  EXISTING_ISSUE_NUMBER=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].number // empty' 2>/dev/null || true)
                  if [ -n "${EXISTING_ISSUE_NUMBER}" ]; then
                    case "${EXISTING_ISSUE_NUMBER}" in
                      *[!0-9]*) EXISTING_ISSUE_NUMBER="" ;;
                    esac
                  fi
                  if [ -n "${EXISTING_ISSUE_NUMBER}" ]; then
                    UPDATES_BULLETS=$(cat "$WORKDIR/critical-updates.md" | tr -d '\\r')
                    COMMENT_BODY=$(jq -rn --arg run_at "$RUN_AT" --arg build "${BUILD_URL:-}" --arg updates "$UPDATES_BULLETS" '
                      "## New breaking updates detected\n\n" +
                      "- **Time:** " + $run_at + "\n" +
                      "- **Build:** " + $build + "\n\n" +
                      "**Updates Available:**\n" + $updates + "\n"
                    ')
                    printf '%s' "$COMMENT_BODY" > "$WORKDIR/comment-body.md"
                    COMMENT_JSON=$(jq -n --arg body "$COMMENT_BODY" '{body:$body}')
                    if ! curl -fsSL -X POST \
                      -H "Authorization: token ${GITHUB_TOKEN}" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "https://api.github.com/repos/${GITHUB_REPO}/issues/${EXISTING_ISSUE_NUMBER}/comments" \
                      -d "$COMMENT_JSON" >/dev/null 2>&1; then
                      echo "⚠️ WARNING: Failed to add comment to existing breaking issue #${EXISTING_ISSUE_NUMBER}"
                    fi
                    echo "Updated existing breaking issue #${EXISTING_ISSUE_NUMBER}"
                    exit 0
                  fi

                  if ! curl -sS -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues" \
                    -d @"$WORKDIR/issue-body.json" >/dev/null 2>&1; then
                    echo "⚠️ WARNING: Failed to create breaking-updates issue"
                  fi
                '''
              }
              createdBreakingIssue = true
            }

            // Also create a PR for non-breaking updates (even if breaking updates exist),
            // so smaller safe bumps (like Rocket.Chat chart 6.29.0 -> 6.30.0) don’t get hidden.
            def shouldCreateNonBreakingPr =
              (highRiskUpdates.size() > 0) ||
              (mediumRiskUpdates.size() > 0) ||
              (terraformVersions?.azurerm?.needsUpdate && terraformVersions?.azurerm?.risk != 'CRITICAL')

            if (shouldCreateNonBreakingPr) {
              echo(createdBreakingIssue
                ? "⚠️ Creating PR for NON-BREAKING updates (breaking issue already created)..."
                : "⚠️ Creating PR for version updates...")
              
              // Write updates to JSON for shell script processing
              def updatesToApply = [
                high: highRiskUpdates,
                medium: mediumRiskUpdates,
                terraform: terraformVersions
              ]
              writeJsonFile('updates-to-apply.json', updatesToApply)
              
              sh '''
                set -e
                WORKDIR="${WORKSPACE:-$(pwd)}"
                export PATH="${WORKDIR}:${PATH}"
                cd "$WORKDIR"
                if [ ! -d .git ]; then
                  echo "Workspace is not a git repository: $WORKDIR"
                  exit 1
                fi
                [ -f "$WORKDIR/ensure_label.sh" ] && . "$WORKDIR/ensure_label.sh" || true

                gitw() {
                  git -C "${WORKDIR}" "$@"
                }

                PR_LIST_JSON=$(curl -fsSL \
                  -H "Authorization: token ${GITHUB_TOKEN}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=dependencies,automated,upgrade&per_page=100" \
                  || echo '[]')
                EXISTING_PR_NUMBER=$(echo "$PR_LIST_JSON" | jq -r '[.[] | select(.pull_request != null) | select(.title | startswith("⬆️ Version Updates:"))][0].number // empty' 2>/dev/null || true)
                if [ -n "${EXISTING_PR_NUMBER}" ]; then
                  case "${EXISTING_PR_NUMBER}" in
                    *[!0-9]*) EXISTING_PR_NUMBER="" ;;
                  esac
                fi
                if [ -n "${EXISTING_PR_NUMBER}" ]; then
                  PR_JSON=$(curl -fsSL \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/pulls/${EXISTING_PR_NUMBER}" \
                    || echo '{}')
                  BRANCH_NAME=$(echo "$PR_JSON" | jq -r '.head.ref // empty' 2>/dev/null || true)
                  echo "Found existing version update PR #${EXISTING_PR_NUMBER} on branch ${BRANCH_NAME}; will update it."
                fi
                BRANCH_NAME="${BRANCH_NAME:-chore/version-updates}"

                # Validate branch name before using it in git commands (defense-in-depth)
                if ! gitw check-ref-format "refs/heads/${BRANCH_NAME}"; then
                  echo "Invalid branch name: ${BRANCH_NAME}"
                  exit 1
                fi

                gitw config user.name "Jenkins Version Bot"
                gitw config user.email "jenkins@canepro.me"
                
                # Check out existing remote branch if it exists
                gitw fetch origin -- "${BRANCH_NAME}" 2>/dev/null || true
                if gitw show-ref --verify --quiet "refs/remotes/origin/${BRANCH_NAME}"; then
                  gitw checkout -B "${BRANCH_NAME}" "origin/${BRANCH_NAME}"
                else
                  gitw checkout -b "${BRANCH_NAME}"
                fi
                
                echo "Applying version updates to files..."
                UPDATE_FAILED=0
                while IFS='|' read -r component current latest location chart; do
                  [ -z "$component" ] || [ -z "$latest" ] || [ "$current" = "$latest" ] && continue
                  echo "Updating $component: $current → $latest in $location"
                  FULL_LOCATION="$WORKDIR/$location"
                  sed -i "s/| \\*\\*${component}\\*\\* | [^|]* |/| **${component}** | ${latest} |/g" "$WORKDIR/VERSIONS.md" 2>/dev/null || UPDATE_FAILED=1
                  sed -i "s/| \\*\\*${component}\\*\\* | [^|]* | [^|]* |.*⚠️/| **${component}** | ${latest} | ${latest} | ✅ **Up to date**/g" "$WORKDIR/VERSIONS.md" 2>/dev/null || true
                  if [ -f "$FULL_LOCATION" ]; then
                    case "$location" in
                      values.yaml)
                        sed -i "s/tag: \"${current}\"/tag: \"${latest}\"/g" "$FULL_LOCATION" 2>/dev/null || UPDATE_FAILED=1
                        ;;
                      terraform/main.tf)
                        sed -i "s/version = \"~> ${current}\"/version = \"~> ${latest}\"/g" "$FULL_LOCATION" 2>/dev/null || UPDATE_FAILED=1
                        ;;
                      GrafanaLocal/argocd/applications/*.yaml)
                        if command -v yq >/dev/null 2>&1 && [ -n "$chart" ]; then
                          yq -i "
                            if .spec.sources then
                              .spec.sources |= map( if (.chart // \"\") == \"$chart\" then .targetRevision = \"$latest\" else . end )
                            else
                              if (.spec.source.chart // \"\") == \"$chart\" then .spec.source.targetRevision = \"$latest\" else . end
                            end
                          " "$FULL_LOCATION" 2>/dev/null || UPDATE_FAILED=1
                        else
                          sed -i "s/targetRevision: ${current}/targetRevision: ${latest}/g" "$FULL_LOCATION" 2>/dev/null || UPDATE_FAILED=1
                        fi
                        if [ "$chart" = "rocketchat" ]; then
                          sed -i "s/Chart: rocketchat\\/rocketchat ${current}/Chart: rocketchat\\/rocketchat ${latest}/g" "$WORKDIR/values.yaml" 2>/dev/null || true
                        fi
                        ;;
                      ops/manifests/*.yaml)
                        sed -i "s/:${current}/:${latest}/g" "$FULL_LOCATION" 2>/dev/null || UPDATE_FAILED=1
                        ;;
                    esac
                  fi
                done < <(jq -r '.high[] + .medium[] | select(.component != null) | "\\(.component)|\\(.current)|\\(.latest)|\\(.location)|\\(.chart // \"\")"' "$WORKDIR/updates-to-apply.json" 2>/dev/null)
                [ "$UPDATE_FAILED" -ne 0 ] && { echo "⚠️ WARNING: One or more manifest updates failed."; exit 1; }

                if [ "$(jq -r '.terraform.azurerm.needsUpdate // false' "$WORKDIR/updates-to-apply.json" 2>/dev/null)" = "true" ]; then
                  TF_RISK=$(jq -r '.terraform.azurerm.risk // ""' "$WORKDIR/updates-to-apply.json" 2>/dev/null || echo "")
                  if [ "$TF_RISK" = "CRITICAL" ]; then
                    echo "Terraform azurerm update is breaking (major); skipping PR update."
                  else
                    CURRENT_TF=$(jq -r '.terraform.azurerm.current' "$WORKDIR/updates-to-apply.json" 2>/dev/null | sed 's/~>//' | tr -d ' ')
                    LATEST_TF=$(jq -r '.terraform.azurerm.latest' "$WORKDIR/updates-to-apply.json" 2>/dev/null)
                    if [ -n "$CURRENT_TF" ] && [ -n "$LATEST_TF" ] && [ "$CURRENT_TF" != "$LATEST_TF" ]; then
                      echo "Updating Terraform Azure Provider: $CURRENT_TF → $LATEST_TF"
                      sed -i "s/| \\*\\*Azure Provider\\*\\* | [^|]* |/| **Azure Provider** | ~> ${LATEST_TF} |/g" "$WORKDIR/VERSIONS.md" || true
                      sed -i "s/version = \"~> ${CURRENT_TF}\"/version = \"~> ${LATEST_TF}\"/g" "$WORKDIR/terraform/main.tf" || true
                    fi
                  fi
                fi
                
                HIGH_COUNT=$(jq '.high | length' "$WORKDIR/updates-to-apply.json" 2>/dev/null || echo "0")
                MEDIUM_COUNT=$(jq '.medium | length' "$WORKDIR/updates-to-apply.json" 2>/dev/null || echo "0")

                VERSION_UPDATES_BODY=$(jq -rn --arg high "$HIGH_COUNT" --arg med "$MEDIUM_COUNT" --arg buildurl "${BUILD_URL:-}" '\''
                  "# Version Updates\n\nThis PR includes automated version updates detected by Jenkins.\n\n## Updates Summary\n- High Risk: " + $high + "\n- Medium Risk: " + $med + "\n\n## Files Updated\n- **VERSIONS.md**: Version tracking automatically updated\n- **Code files**: Actual version numbers updated (values.yaml, terraform/main.tf, etc.)\n\n## Review Checklist\n- [ ] Review all version changes in VERSIONS.md\n- [ ] Verify code file changes are correct\n- [ ] Check release notes for breaking changes\n- [ ] Test in staging if applicable\n\nBuild: " + $buildurl
                '\'')
                printf '%s' "$VERSION_UPDATES_BODY" > "$WORKDIR/VERSION_UPDATES.md"

                gitw add VERSIONS.md VERSION_UPDATES.md values.yaml terraform/main.tf ops/manifests/*.yaml 2>/dev/null || true

                # If there is nothing to commit, skip pushing/PR creation
                if gitw diff --cached --quiet; then
                  echo "No staged changes; skipping PR creation."
                  exit 0
                fi
                
                # Commit with detailed message
                gitw commit -m "chore: automated version updates

                - High risk: ${HIGH_COUNT}
                - Medium risk: ${MEDIUM_COUNT}
                - Updated VERSIONS.md automatically
                - Updated code files with new versions
                - Generated by Jenkins version check pipeline" || echo "No changes to commit"
                
                # Push without persisting credentials in .git/config (avoid embedding token in remote URL)
                # Use HTTPS explicitly so this works even if the checkout remote is SSH.
                set +x
                ASKPASS="$(mktemp)"
                cleanup_askpass() {
                  rm -f "$ASKPASS" || true
                  unset GIT_ASKPASS GIT_TERMINAL_PROMPT
                }
                trap cleanup_askpass EXIT
                cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) echo "x-access-token" ;;
  *Password*) echo "$GITHUB_TOKEN" ;;
  *) echo "" ;;
esac
EOF
                chmod 700 "$ASKPASS"
                export GIT_ASKPASS="$ASKPASS"
                export GIT_TERMINAL_PROMPT=0

                gitw push "https://github.com/${GITHUB_REPO}.git" -- "HEAD:${BRANCH_NAME}"

                # Keep xtrace disabled for subsequent commands that include secrets (curl Authorization headers).

                ensure_label "dependencies" "0366d6"
                ensure_label "automated" "0e8a16"
                ensure_label "upgrade" "fbca04"
                
                # Create PR
                PR_BODY=$(jq -rn --arg high "$HIGH_COUNT" --arg med "$MEDIUM_COUNT" --arg buildurl "${BUILD_URL:-}" '\''
                  "## Automated Version Updates\n\nThis PR includes version updates detected by automated checks.\n\n### Updates Summary\n- High Risk: " + $high + "\n- Medium Risk: " + $med + "\n\n### Files Updated\n- **VERSIONS.md**: Automatically updated with new versions\n- **Code files**: Version numbers updated in values.yaml, terraform/main.tf, etc.\n\n### Review Checklist\n- [ ] Review all version changes in VERSIONS.md\n- [ ] Verify code file changes are correct\n- [ ] Check release notes for breaking changes\n- [ ] Test in staging if applicable\n\nBuild: " + $buildurl + "\n\n---\n*This PR was automatically created by Jenkins version check pipeline.*"
                '\'')
                jq -n --arg title "⬆️ Version Updates: ${HIGH_COUNT} high, ${MEDIUM_COUNT} medium" --arg head "${BRANCH_NAME}" --arg base "master" --arg body "$PR_BODY" \
                  '{title:$title, head:$head, base:$base, body:$body}' > "$WORKDIR/pr-body.json"

                PR_CREATE_JSON=$(curl -sS -X POST \
                  -H "Authorization: token ${GITHUB_TOKEN}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "https://api.github.com/repos/${GITHUB_REPO}/pulls" \
                  -d @"$WORKDIR/pr-body.json" 2>/dev/null || echo '{}')
                if ! echo "$PR_CREATE_JSON" | jq -e '.number' >/dev/null 2>&1; then
                  echo "⚠️ WARNING: Failed to create PR (response may contain errors)"
                fi
                PR_CREATED_NUMBER=$(echo "$PR_CREATE_JSON" | jq -r '.number // empty' 2>/dev/null || true)
                if [ -n "${PR_CREATED_NUMBER}" ]; then
                  if ! curl -sS -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_CREATED_NUMBER}/labels" \
                    -d '{"labels":["dependencies","automated","upgrade"]}' >/dev/null 2>&1; then
                    echo "⚠️ WARNING: Failed to add labels to PR #${PR_CREATED_NUMBER}"
                  fi
                fi

                # If we updated an existing PR branch, add a comment so changes aren’t missed.
                if [ -n "${EXISTING_PR_NUMBER:-}" ]; then
                  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                  # Build optional build line in shell so jq receives a single safe string (avoids jq ternary quoting issues)
                  BUILD_LINE=""
                  if [ -n "${BUILD_URL:-}" ]; then
                    BUILD_LINE=$(printf '\nBuild: %s' "${BUILD_URL}")
                  fi
                  COMMENT_JSON=$(jq -n --arg ts "$TS" --arg buildline "$BUILD_LINE" --arg high "${HIGH_COUNT}" --arg med "${MEDIUM_COUNT}" \
                    '{body:("## PR updated by Jenkins\n\nTime: " + $ts + $buildline + "\n\nUpdates summary:\n- High Risk: " + $high + "\n- Medium Risk: " + $med)}')
                  if ! curl -fsSL -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues/${EXISTING_PR_NUMBER}/comments" \
                    -d "$COMMENT_JSON" >/dev/null 2>&1; then
                    echo "⚠️ WARNING: Failed to add comment to existing PR #${EXISTING_PR_NUMBER}"
                  fi
                fi
              '''
            } else if (!createdBreakingIssue) {
              echo "✅ All versions are up to date or updates are low risk"
            } else {
              echo "✅ Breaking updates detected and issue created; no non-breaking PR updates to apply."
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
            WORKDIR="${WORKSPACE:-$(pwd)}"
            export PATH="${WORKDIR}:${PATH}"
            ISSUE_TITLE="CI Failure: ${JOB_NAME}"
            if [ -f "$WORKDIR/ensure_label.sh" ]; then
              . "$WORKDIR/ensure_label.sh"
            else
              ensure_label() {
                LABEL_JSON=$(jq -n --arg name "$1" --arg color "$2" '{name:$name,color:$color}')
                curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/labels/$1" >/dev/null 2>&1 && return 0
                curl -fsSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${GITHUB_REPO}/labels" -d "$LABEL_JSON" >/dev/null 2>&1 || true
              }
            fi
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
              if ! curl -sS -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" \
                -d "$COMMENT_JSON" >/dev/null 2>&1; then
                echo "⚠️ WARNING: Failed to add comment to existing failure issue #${ISSUE_NUMBER}"
              fi
              echo "Updated existing failure issue: ${ISSUE_URL}"
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
            ISSUE_BODY_JSON=$(jq -n --arg title "$ISSUE_TITLE" --arg body "$FAIL_BODY" \
              '{title:$title, body:$body, labels:["ci","jenkins","failure","automated"]}')
            echo "$ISSUE_BODY_JSON" > "$WORKDIR/issue-body-failure.json"
            if ! curl -sS -X POST \
              -H "Authorization: token ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/${GITHUB_REPO}/issues" \
              -d @"$WORKDIR/issue-body-failure.json" >/dev/null 2>&1; then
              echo "⚠️ WARNING: Failed to create failure issue"
            fi
          '''
        }
      }
    }
  }
}

@NonCPS
String jsonEscape(String value) {
  if (value == null) {
    return ""
  }
  return value
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")
    .replace("\r", "\\r")
    .replace("\n", "\\n")
    .replace("\t", "\\t")
}

@NonCPS
String toJson(Object value) {
  if (value == null) {
    return "null"
  }
  if (value instanceof Map) {
    def entries = []
    value.each { k, v ->
      def key = jsonEscape(k?.toString())
      entries.add("\"${key}\":${toJson(v)}")
    }
    return "{${entries.join(',')}}"
  }
  if (value instanceof List) {
    def items = value.collect { item -> toJson(item) }
    return "[${items.join(',')}]"
  }
  if (value instanceof Boolean || value instanceof Number) {
    return value.toString()
  }
  return "\"${jsonEscape(value.toString())}\""
}

// Write JSON without Pipeline Utility Steps plugin or groovy.json classes.
def writeJsonFile(String path, Object data) {
  writeFile file: path, text: toJson(data)
}

// Parse major version number from a version string (constraint or plain semver).
// Handles Terraform-style constraints (e.g. "~>3.0", ">=4.2.1") and plain semver ("4.58.0").
// Returns 0 for null, empty, or unparseable input so callers get a safe comparison.
def parseMajorVersion(String v) {
  if (v == null) return 0
  def s = v.trim()
  if (!s) return 0
  def cleaned = s.replaceAll(/^[^0-9]+/, '').trim()
  def segment = cleaned.split('\\.')[0]?.trim()
  return (segment ==~ /[0-9]+/) ? segment.toInteger() : 0
}

// Returns true if latest is a higher major version than current (e.g. 3.x -> 4.x).
def isMajorVersionUpdate(current, latest) {
  def currentMajor = parseMajorVersion(current?.toString())
  def latestMajor = parseMajorVersion(latest?.toString())
  return latestMajor > currentMajor
}
