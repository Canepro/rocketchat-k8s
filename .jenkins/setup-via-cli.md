# Setting Up Jenkins Jobs via CLI

If the Jenkins UI is not working for you, you can create Multibranch Pipeline jobs via CLI using several methods.

## Method 1: Jenkins CLI (Recommended)

### Prerequisites
1. Install Jenkins CLI client (or use the one bundled with Jenkins)
2. Get your Jenkins API token: **Manage Jenkins** → **Users** → **Your User** → **Configure** → **API Token** → **Add new token**

### Create Job via CLI

```bash
# Set Jenkins URL and credentials
export JENKINS_URL="https://jenkins.canepro.me"
export JENKINS_USER="admin"
export JENKINS_TOKEN="your-api-token-here"

# Create the Multibranch Pipeline job from XML config
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_TOKEN" \
  -H "Content-Type: application/xml" \
  --data-binary @.jenkins/job-config.xml \
  "$JENKINS_URL/createItem?name=rocketchat-k8s"
```

### Verify Job Created

```bash
# Check if job exists
curl -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/job/rocketchat-k8s/api/json"

# Trigger initial scan
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/job/rocketchat-k8s/build?delay=0sec"
```

---

## Method 2: Jenkins REST API (Alternative)

### Create Job

```bash
# Create job from XML configuration
curl -X POST \
  -u "admin:YOUR_API_TOKEN" \
  -H "Content-Type: application/xml" \
  --data-binary @.jenkins/job-config.xml \
  "https://jenkins.canepro.me/createItem?name=rocketchat-k8s"
```

### Trigger Scan

```bash
# Trigger branch scan
curl -X POST \
  -u "admin:YOUR_API_TOKEN" \
  "https://jenkins.canepro.me/job/rocketchat-k8s/scan"
```

---

## Method 3: Jenkins Configuration as Code (JCasC)

Add this to your `jenkins-values.yaml` under `controller.JCasC.configScripts`:

```yaml
controller:
  JCasC:
    configScripts:
      # ... existing configs ...
      
      # Multibranch Pipeline Job for rocketchat-k8s
      rocketchat-k8s-job: |
        jobs:
          - multibranch:
              name: "rocketchat-k8s"
              description: "CI validation pipeline for rocketchat-k8s repository"
              sources:
                - github:
                    id: "github-rocketchat-k8s"
                    credentialsId: "github-token"
                    repoOwner: "Canepro"
                    repository: "rocketchat-k8s"
                    traits:
                      - branchDiscovery:
                          strategyId: 1  # Exclude branches that are also filed as PRs
                      - originPullRequestDiscovery:
                          strategyId: 1  # The current pull request revision
                      - forkPullRequestDiscovery:
                          strategyId: 1  # The current pull request revision
                          trust: "Contributors"
              scriptPath: ".jenkins/terraform-validation.Jenkinsfile"
              orphanedItemStrategy:
                pruneDeadBranches: true
```

**Note**: JCasC job configuration syntax may vary by plugin versions. If this doesn't work, use Method 1 or 2.

---

## Method 4: Using kubectl exec (Direct Access)

If you have kubectl access to the Jenkins pod:

```bash
# Get Jenkins pod name
kubectl get pods -n jenkins

# Get admin password
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d

# Create job via CLI inside pod
kubectl exec -n jenkins jenkins-0 -c jenkins -- \
  java -jar /usr/share/jenkins/jenkins.war \
  -s https://jenkins.canepro.me \
  -auth admin:PASSWORD \
  create-job rocketchat-k8s < .jenkins/job-config.xml
```

---

## Quick Setup Script

Save this as `setup-jenkins-job.sh`:

```bash
#!/bin/bash
set -e

# Configuration
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
JOB_NAME="${JOB_NAME:-rocketchat-k8s}"
CONFIG_FILE="${CONFIG_FILE:-.jenkins/job-config.xml}"

# Get credentials
echo "Enter Jenkins admin username (default: admin):"
read -r JENKINS_USER
JENKINS_USER="${JENKINS_USER:-admin}"

echo "Enter Jenkins admin password (or API token):"
read -rs JENKINS_PASSWORD

# Create job
echo "Creating job: $JOB_NAME"
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "Content-Type: application/xml" \
  --data-binary @"$CONFIG_FILE" \
  "$JENKINS_URL/createItem?name=$JOB_NAME"

if [ $? -eq 0 ]; then
  echo "✅ Job created successfully!"
  
  # Trigger scan
  echo "Triggering initial scan..."
  curl -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    "$JENKINS_URL/job/$JOB_NAME/scan"
  
  echo "✅ Initial scan triggered!"
  echo "Check job status at: $JENKINS_URL/job/$JOB_NAME"
else
  echo "❌ Failed to create job"
  exit 1
fi
```

**Usage**:
```bash
chmod +x setup-jenkins-job.sh
./setup-jenkins-job.sh
```

---

## Troubleshooting

### Job Already Exists
If the job already exists, delete it first:
```bash
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/rocketchat-k8s/doDelete"
```

### Invalid Credentials
Make sure you're using:
- API Token (not password) for REST API calls, OR
- Username + Password for basic auth

Get API token: **Manage Jenkins** → **Users** → **Your User** → **Configure** → **API Token**

### XML Validation Errors
The XML config may need adjustment based on your Jenkins plugin versions. Check Jenkins logs:
```bash
kubectl logs -n jenkins jenkins-0 -c jenkins --tail=50
```

---

## Next Steps After Creating Job

1. **Verify job exists**: Check Jenkins UI or via API
2. **Trigger scan**: Job will auto-scan, or trigger manually
3. **Check discovered branches**: Should see `master` branch and any PRs
4. **Test with PR**: Create a test PR to verify validation runs
