// Terraform Validation Pipeline for rocketchat-k8s
// This pipeline validates Terraform infrastructure code including plan generation.
// Uses Azure Workload Identity for authentication.
// Runs on the static AKS agent (aks-agent) so it uses AKS Workload Identity and avoids OKE; AKS has auto-shutdown.
pipeline {
  agent { label 'aks-agent' }

  options {
    // Avoid Jenkins' implicit SCM checkout so we can wipe stale workspaces first.
    skipDefaultCheckout(true)
  }
  
  environment {
    // Azure Storage remote backend for Terraform state.
    // Override these in Jenkins job configuration only if you need a different backend.
    TF_BACKEND_RESOURCE_GROUP = "${env.TF_BACKEND_RESOURCE_GROUP ?: 'rg-canepro-tfstate'}"
    TF_BACKEND_STORAGE_ACCOUNT = "${env.TF_BACKEND_STORAGE_ACCOUNT ?: 'caneprotfgmhl5a'}"
    TF_BACKEND_CONTAINER = "${env.TF_BACKEND_CONTAINER ?: 'tfstate'}"
    TF_BACKEND_KEY = "${env.TF_BACKEND_KEY ?: 'aks.terraform.tfstate'}"
    GITHUB_TOKEN_CREDENTIALS = 'github-token'
    PIPELINEHEALER_BRIDGE_URL_CREDENTIALS = 'pipelinehealer-bridge-url'
    PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS = 'pipelinehealer-bridge-secret'
    PH_FAILURE_STEP = ''
    PH_FAILURE_COMMAND = ''

    // Non-secret defaults so CI plans match interactive plans (override in job config if needed)
    TF_VAR_jenkins_graceful_disconnect_url = "${env.TF_VAR_jenkins_graceful_disconnect_url ?: 'https://jenkins.canepro.me'}"
    TF_VAR_jenkins_graceful_disconnect_user = "${env.TF_VAR_jenkins_graceful_disconnect_user ?: 'admin'}"
    TF_VAR_jenkins_graceful_disconnect_agent_name = "${env.TF_VAR_jenkins_graceful_disconnect_agent_name ?: 'aks-agent'}"
  }
  
  stages {
    // Stage 1: Start from a clean workspace before any PR merge checkout occurs.
    stage('Checkout') {
      steps {
        script {
          env.PH_FAILURE_STEP = 'Checkout'
        }
        deleteDir()
        script {
          if (env.CHANGE_ID) {
            env.PH_FAILURE_COMMAND = "git fetch refs/pull/${env.CHANGE_ID}/merge and checkout merge ref"
            withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
              sh '''
                set -eu
                ASKPASS="$(mktemp)"
                cleanup_askpass() {
                  rm -f "$ASKPASS"
                  unset GIT_ASKPASS GIT_TERMINAL_PROMPT
                }
                trap cleanup_askpass EXIT

                cat >"$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "$GITHUB_USER" ;;
  *) printf '%s\n' "$GITHUB_TOKEN" ;;
esac
EOF
                chmod 700 "$ASKPASS"
                export GIT_ASKPASS="$ASKPASS"
                export GIT_TERMINAL_PROMPT=0

                git init .
                git remote add origin https://github.com/Canepro/rocketchat-k8s.git
                git fetch --no-tags --force --progress origin "refs/pull/${CHANGE_ID}/merge"
                git checkout -f FETCH_HEAD
              '''
            }
          } else {
            env.PH_FAILURE_COMMAND = 'checkout scm'
            checkout scm
          }
          env.GIT_COMMIT = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
        }
      }
    }

    // Stage 2: Install Terraform (extract to workspace with Python so no unzip/root needed)
    stage('Setup') {
      steps {
        script {
          env.PH_FAILURE_STEP = 'Setup'
          env.PH_FAILURE_COMMAND = 'Download Terraform from HashiCorp releases and install into workspace'
        }
        sh '''
          cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          set -e
          # Ensure extraction tools exist; try to install python3/unzip when missing.
          if ! command -v python3 >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
            if command -v apk >/dev/null 2>&1; then
              apk add --no-cache python3 unzip 2>/dev/null || true
            elif command -v apt-get >/dev/null 2>&1; then
              (apt-get update -qq && apt-get install -y python3 unzip) 2>/dev/null || true
            elif command -v yum >/dev/null 2>&1; then
              yum install -y python3 unzip 2>/dev/null || true
            elif command -v tdnf >/dev/null 2>&1; then
              tdnf install -y python3 unzip 2>/dev/null || true
            fi
          fi
          # Azure CLI (optional): try user install if python3 exists; no root required.
          WORKDIR="${WORKSPACE:-$(pwd)}"
          if ! command -v az >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
            python3 -m pip install --quiet --no-cache-dir --user azure-cli || true
            export PATH="${HOME:-/tmp}/.local/bin:${PATH}"
          fi
          if command -v az >/dev/null 2>&1; then
            echo "Azure CLI available"
            touch "$WORKDIR/.az_available"
          else
            echo "Azure CLI not available; Azure Login stage will be skipped"
            rm -f "$WORKDIR/.az_available"
          fi
          WORKDIR="${WORKSPACE:-$(pwd)}"
          TF_BIN_DIR="${WORKDIR}/.bin"
          mkdir -p "$TF_BIN_DIR"
          TERRAFORM_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | grep -o '"current_version":"[^"]*' | cut -d'"' -f4)
          curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o terraform.zip
          TMP_TF_DIR="$(mktemp -d)"
          if command -v python3 >/dev/null 2>&1; then
            python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" terraform.zip "$TMP_TF_DIR"
          elif command -v unzip >/dev/null 2>&1; then
            unzip -o terraform.zip -d "$TMP_TF_DIR" >/dev/null
          elif command -v jar >/dev/null 2>&1; then
            # Use JDK jar tool if unzip/python3 are unavailable.
            (cd "$TMP_TF_DIR" && jar xf "$WORKDIR/terraform.zip")
          else
            echo "No tool available to extract terraform.zip (python3, unzip, or jar)"
            exit 1
          fi
          if [ ! -f "$TMP_TF_DIR/terraform" ]; then
            echo "Terraform binary not found after extraction"
            exit 1
          fi
          mv "$TMP_TF_DIR/terraform" "$TF_BIN_DIR/terraform"
          rm -rf "$TMP_TF_DIR" terraform.zip
          chmod +x "$TF_BIN_DIR/terraform"
          export PATH="${TF_BIN_DIR}:${PATH}"
          terraform version
SCRIPT
        '''
      }
    }
    
    // Stage 3: Verify Azure Workload Identity
    stage('Verify Azure Auth') {
      steps {
        script {
          env.PH_FAILURE_STEP = 'Verify Azure Auth'
          env.PH_FAILURE_COMMAND = 'Validate ARM and workload-identity environment variables and token file'
        }
        sh '''
          cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          set -e
          echo "=== Verifying Azure Workload Identity Configuration ==="
          
          # Check required environment variables
          if [ -z "${ARM_CLIENT_ID:-}" ]; then
            echo "ERROR: ARM_CLIENT_ID not set"
            exit 1
          fi
          if [ -z "${ARM_TENANT_ID:-}" ]; then
            echo "ERROR: ARM_TENANT_ID not set"
            exit 1
          fi
          if [ -z "${ARM_SUBSCRIPTION_ID:-}" ]; then
            echo "ERROR: ARM_SUBSCRIPTION_ID not set"
            exit 1
          fi
          if [ -z "${AZURE_FEDERATED_TOKEN_FILE:-}" ]; then
            echo "ERROR: AZURE_FEDERATED_TOKEN_FILE not set"
            exit 1
          fi
          
          # Verify token file exists and is readable
          if [ ! -f "$AZURE_FEDERATED_TOKEN_FILE" ]; then
            echo "ERROR: Token file not found at $AZURE_FEDERATED_TOKEN_FILE"
            exit 1
          fi
          
          echo "✓ Client ID: ${ARM_CLIENT_ID}"
          echo "✓ Tenant ID: ${ARM_TENANT_ID}"
          echo "✓ Subscription ID: ${ARM_SUBSCRIPTION_ID}"
          echo "✓ Token file: ${AZURE_FEDERATED_TOKEN_FILE}"
          echo "✓ Token file size: $(wc -c < $AZURE_FEDERATED_TOKEN_FILE) bytes"
          echo ""
          echo "Workload Identity is configured. Terraform will authenticate using OIDC token."
SCRIPT
        '''
      }
    }
    
    // Stage 4: Format Check
    stage('Terraform Format') {
      steps {
        dir('terraform') {
          script {
            env.PH_FAILURE_STEP = 'Terraform Format'
            env.PH_FAILURE_COMMAND = 'terraform fmt -check -recursive'
          }
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            export PATH="${WORKSPACE}/.bin:${PATH}"
            terraform fmt -check -recursive
SCRIPT
          '''
        }
      }
    }
    
    // Stage 5: Terraform Init & Validate
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          script {
            env.PH_FAILURE_STEP = 'Terraform Validate'
            env.PH_FAILURE_COMMAND = 'terraform init (backend + OIDC auth) and terraform validate'
          }
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            export PATH="${WORKSPACE}/.bin:${PATH}"
            if [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]; then
              export ARM_OIDC_TOKEN_FILE="${AZURE_FEDERATED_TOKEN_FILE}"
            fi
            unset TF_VAR_budget_alert_email
            echo "INFO: Initializing terraform backend ${TF_BACKEND_STORAGE_ACCOUNT}/${TF_BACKEND_CONTAINER}/${TF_BACKEND_KEY}"
            terraform init \
              -backend-config="resource_group_name=${TF_BACKEND_RESOURCE_GROUP}" \
              -backend-config="storage_account_name=${TF_BACKEND_STORAGE_ACCOUNT}" \
              -backend-config="container_name=${TF_BACKEND_CONTAINER}" \
              -backend-config="key=${TF_BACKEND_KEY}" \
              -backend-config="use_oidc=true" \
              -backend-config="use_azuread_auth=true" \
              -backend-config="tenant_id=${ARM_TENANT_ID}" \
              -backend-config="client_id=${ARM_CLIENT_ID}" \
              -backend-config="subscription_id=${ARM_SUBSCRIPTION_ID}"

            terraform validate
SCRIPT
          '''
        }
      }
    }
    
    // Stage 6: Prepare tfvars for validation
    stage('Get Variables') {
      steps {
        dir('terraform') {
          script {
            env.PH_FAILURE_STEP = 'Get Variables'
            env.PH_FAILURE_COMMAND = 'Generate terraform.tfvars + zz_ci.auto.tfvars for CI'
          }
          withCredentials([string(credentialsId: 'budget-alert-email', variable: 'BUDGET_ALERT_EMAIL')]) {
            sh '''
              cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
              export PATH="${WORKSPACE}/.bin:${PATH}"
              # Use example file for CI validation, then override placeholder-only values with Jenkins secrets.
              echo "INFO: Using example tfvars for validation (placeholder values)"
              cp terraform.tfvars.example terraform.tfvars
              if [ -n "${BUDGET_ALERT_EMAIL:-}" ]; then
                BUDGET_ALERT_EMAIL_ESCAPED="$(printf '%s' "${BUDGET_ALERT_EMAIL}" | awk '{gsub(/\\\\/,\"\\\\\\\\\"); gsub(/\"/,\"\\\\\\\"\"); print}')"
                BUDGET_ALERT_EMAIL_VALUE="${BUDGET_ALERT_EMAIL_ESCAPED}"
                echo "INFO: Overriding budget_alert_email from Jenkins credential"
              else
                BUDGET_ALERT_EMAIL_VALUE="REPLACE_ME@example.com"
                echo "INFO: budget-alert-email credential is empty; using placeholder override to keep CI deterministic"
              fi
              printf 'budget_alert_email = "%s"\n' "${BUDGET_ALERT_EMAIL_VALUE}" > zz_ci.auto.tfvars
SCRIPT
            '''
          }
        }
      }
    }
    
    // Stage 7: Terraform Plan
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          script {
            env.PH_FAILURE_STEP = 'Terraform Plan'
            env.PH_FAILURE_COMMAND = 'terraform plan -detailed-exitcode (-refresh=false fallback)'
          }
          sh '''
            cat <<'SCRIPT' | sh "${WORKSPACE}/.jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh" "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            export PATH="${WORKSPACE}/.bin:${PATH}"
            if [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]; then
              export ARM_OIDC_TOKEN_FILE="${AZURE_FEDERATED_TOKEN_FILE}"
            fi
            unset TF_VAR_budget_alert_email
            echo "INFO: Planning against terraform backend ${TF_BACKEND_STORAGE_ACCOUNT}/${TF_BACKEND_CONTAINER}/${TF_BACKEND_KEY}"
            PLAN_EXIT=0
            PLAN_ERR_FILE="$(mktemp)"
            cleanup_plan_err() {
              rm -f "${PLAN_ERR_FILE}"
            }
            trap cleanup_plan_err EXIT

            terraform plan \
              -no-color \
              -input=false \
              -out=tfplan \
              -detailed-exitcode \
              -refresh=true 2>"${PLAN_ERR_FILE}" || PLAN_EXIT=$?

            case "${PLAN_EXIT:-0}" in
              0|2)
                ;;
              1)
                if grep -Eiq '(Error refreshing state|Failed to read remote state|Error loading state|Error acquiring the state lock|Error loading backend|state snapshot|context deadline exceeded|TLS handshake timeout|connection reset by peer|i/o timeout)' "${PLAN_ERR_FILE}"; then
                  echo "Terraform plan failed with refresh/state-related error; retrying with refresh disabled to isolate config errors."
                  PLAN_EXIT=0
                  terraform plan \
                    -no-color \
                    -input=false \
                    -out=tfplan \
                    -detailed-exitcode \
                    -refresh=false 2>"${PLAN_ERR_FILE}" || PLAN_EXIT=$?
                  case "${PLAN_EXIT:-0}" in
                    0|2)
                      ;;
                    1)
                      echo "Terraform plan failed"
                      cat "${PLAN_ERR_FILE}" >&2
                      exit 1
                      ;;
                    *)
                      echo "Terraform plan exited unexpectedly with status ${PLAN_EXIT}" >&2
                      cat "${PLAN_ERR_FILE}" >&2
                      exit "${PLAN_EXIT}"
                      ;;
                  esac
                else
                  echo "Terraform plan failed with non-refresh error; skipping refresh-disabled retry."
                  cat "${PLAN_ERR_FILE}" >&2
                  exit 1
                fi
                ;;
              *)
                echo "Terraform plan exited unexpectedly with status ${PLAN_EXIT}" >&2
                cat "${PLAN_ERR_FILE}" >&2
                exit "${PLAN_EXIT}"
                ;;
            esac

            if [ "${PLAN_EXIT:-0}" = "2" ]; then
              echo "Changes detected in plan"
            else
              echo "No changes detected"
            fi
SCRIPT
          '''
        }
      }
    }
  }
  
  post {
    always {
      // Archive plan for review
      dir('terraform') {
        sh 'export PATH="${WORKSPACE}/.bin:${PATH}" && terraform show -no-color tfplan > tfplan.txt 2>/dev/null || true'
        archiveArtifacts artifacts: 'tfplan.txt', allowEmptyArchive: true
      }
    }
    cleanup {
      cleanWs()
    }
    success {
      echo '✅ Terraform validation passed'
      script {
        env.PH_JOB_FRAGMENT = "/job/${(env.JOB_NAME ?: '').replace('/', '/job/')}/"
      }
      withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
        sh '''
          set -eu
          API_BASE="https://api.github.com/repos/Canepro/rocketchat-k8s"
          JOB_FRAGMENT="${PH_JOB_FRAGMENT:-}"

          if [ -z "$JOB_FRAGMENT" ]; then
            echo "No JOB_FRAGMENT available; skipping stale issue auto-close."
            exit 0
          fi

          MATCHING_ISSUES="$(perl -MJSON::PP=decode_json -e '
            use strict;
            use warnings;

            my ($api_base, $job_fragment) = @ARGV;
            my $token = $ENV{GITHUB_TOKEN} // q{};
            die q{missing GITHUB_TOKEN} if $token eq q{};
            my @matches = ();

            for my $page (1..10) {
              my $url = sprintf("%s/issues?state=open&labels=ci-failure,pipelinehealer&per_page=100&page=%d", $api_base, $page);
              open my $fh, q{-|},
                q{curl},
                q{-fsSL},
                q{-H}, qq{Authorization: token $token},
                q{-H}, q{Accept: application/vnd.github+json},
                q{-H}, q{X-GitHub-Api-Version: 2022-11-28},
                $url
                or die qq{failed to run curl for $url: $!};
              local $/ = undef;
              my $raw = <$fh>;
              close $fh;
              die qq{curl failed for $url} if $?;
              my $items = eval { decode_json($raw) };
              last if $@ || ref($items) ne "ARRAY" || scalar(@$items) == 0;

              for my $issue (@$items) {
                next if ref($issue) ne "HASH";
                next if exists $issue->{pull_request};
                my $title = $issue->{title} // q{};
                my $body  = $issue->{body}  // q{};
                next unless $title =~ /^\\[PipelineHealer\\]/;
                next unless index($body, $job_fragment) >= 0;
                push @matches, $issue->{number};
              }

              last if scalar(@$items) < 100;
            }

            print join("\\n", @matches);
          ' "$API_BASE" "$JOB_FRAGMENT")"

          if [ -z "$MATCHING_ISSUES" ]; then
            echo "No stale PipelineHealer issues matched this job."
            exit 0
          fi

          while IFS= read -r issue_number; do
            [ -n "$issue_number" ] || continue
            COMMENT_TEXT="Closing automatically after successful Jenkins validation run ${BUILD_URL} on commit ${GIT_COMMIT}."
            COMMENT_PAYLOAD="$(perl -MJSON::PP=encode_json -e 'print encode_json({ body => $ARGV[0] })' "$COMMENT_TEXT")"

            curl -fsSL \
              -X POST \
              -H "Authorization: token ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github+json" \
              -H "X-GitHub-Api-Version: 2022-11-28" \
              -H "Content-Type: application/json" \
              "${API_BASE}/issues/${issue_number}/comments" \
              -d "${COMMENT_PAYLOAD}" >/dev/null

            curl -fsSL \
              -X PATCH \
              -H "Authorization: token ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github+json" \
              -H "X-GitHub-Api-Version: 2022-11-28" \
              -H "Content-Type: application/json" \
              "${API_BASE}/issues/${issue_number}" \
              -d '{"state":"closed"}' >/dev/null

            echo "Closed stale PipelineHealer issue #${issue_number}"
          done <<EOF
$MATCHING_ISSUES
EOF
        '''
      }
    }
    failure {
      echo '❌ Terraform validation failed'
      script {
        try {
          env.PH_DURATION_MS = "${currentBuild.duration}"
          withCredentials([
            string(credentialsId: "${env.PIPELINEHEALER_BRIDGE_URL_CREDENTIALS}", variable: 'PH_BRIDGE_URL'),
            string(credentialsId: "${env.PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS}", variable: 'PH_BRIDGE_SECRET'),
          ]) {
            echo 'PipelineHealer bridge: entering failure handler'
            if (fileExists('.jenkins/scripts/send-pipelinehealer-bridge.sh')) {
              def groovyExists = fileExists('.jenkins/scripts/pipelinehealer-bridge-evidence.groovy')
              echo "PipelineHealer bridge: evidence groovy exists=${groovyExists}"
              if (groovyExists) {
                echo 'PipelineHealer bridge: loading Groovy fallback helper'
                def bridgeEvidence = load '.jenkins/scripts/pipelinehealer-bridge-evidence.groovy'
                def result = bridgeEvidence.writeLogExcerpt()
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
                export PH_FAILURE_STEP="${PH_FAILURE_STEP:-terraform-validation}"
                export PH_FAILURE_COMMAND="${PH_FAILURE_COMMAND:-terraform command failure}"
                export PH_BRANCH="${PH_BRANCH_VALUE}"
                export PH_COMMIT_SHA="${GIT_COMMIT:-}"
                export PH_FAILURE_STAGE="terraform-validation"
                export PH_FAILURE_SUMMARY="Jenkins Terraform validation failed"
                export PH_RESULT="FAILURE"
                if [ -f "${WORKSPACE}/.pipelinehealer-log-excerpt.txt" ]; then
                  export PH_LOG_EXCERPT_FILE="${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
                fi
                export PH_DURATION_MS="${PH_DURATION_MS:-0}"
                bash .jenkins/scripts/send-pipelinehealer-bridge.sh >/dev/null || \
                  echo "⚠️ WARNING: Failed to notify PipelineHealer bridge"
              '''
            } else {
              echo '⚠️ PipelineHealer bridge script unavailable in workspace; skipping bridge notification.'
            }
          }
        } catch (err) {
          echo "⚠️ PipelineHealer bridge credentials not configured; skipping bridge notification."
        }
      }
    }
  }
}
