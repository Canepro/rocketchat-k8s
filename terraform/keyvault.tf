# Terraform Configuration: Azure Key Vault for GitOps Secrets Management
# This file provisions Azure Key Vault infrastructure for GitOps secrets management via External Secrets Operator.
# It includes: Key Vault, User Assigned Managed Identity, RBAC role assignments, and secret values.
# Azure Key Vault for GitOps secrets management (External Secrets Operator)
# This provisions the Key Vault infrastructure AND secret values (from terraform.tfvars)
# See VERSIONS.md for External Secrets Operator version tracking (managed by Helm chart via ArgoCD).

# User Assigned Managed Identity for External Secrets Operator
# This UAMI is used by External Secrets Operator to authenticate to Azure Key Vault via Azure Workload Identity.
# The UAMI's client ID is referenced in ClusterSecretStore (ops/secrets/clustersecretstore-azure-keyvault.yaml).
resource "azurerm_user_assigned_identity" "eso" {
  name                = "${var.cluster_name}-eso-identity"  # UAMI name (from variables.tf, e.g., "aks-canepro-eso-identity")
  location            = azurerm_resource_group.main.location  # Azure region (from resource group)
  resource_group_name = azurerm_resource_group.main.name  # Resource group (from main.tf)

  tags = merge(var.tags, {
    Purpose = "ExternalSecretsOperator"  # Purpose tag (for resource organization)
  })
}

# Azure Key Vault: Secure storage for Rocket.Chat secrets
# This Key Vault stores all Rocket.Chat secrets (MongoDB credentials, connection strings, etc.).
# Secrets are synced from Key Vault to Kubernetes Secrets by External Secrets Operator.
# Azure Key Vault
resource "azurerm_key_vault" "rocketchat" {
  # Key Vault name must be globally unique (24 chars max, alphanumeric and hyphens only)
  # Name format: <cluster-name>-kv-<hash> (hash ensures uniqueness)
  name                       = "${var.cluster_name}-kv-${substr(md5(azurerm_resource_group.main.id), 0, 6)}"  # Key Vault name (globally unique)
  location                   = azurerm_resource_group.main.location  # Azure region (from resource group)
  resource_group_name        = azurerm_resource_group.main.name  # Resource group (from main.tf)
  tenant_id                  = data.azurerm_client_config.current.tenant_id  # Azure AD tenant ID (from current client config)
  sku_name                   = var.key_vault_sku  # Key Vault SKU (from variables.tf, default: "standard")
  soft_delete_retention_days = 7  # Soft delete retention (days before permanent deletion)
  purge_protection_enabled   = var.key_vault_purge_protection  # Purge protection (from variables.tf, default: false)

  # Network access: public by default (can be restricted via network_acls if needed)
  # Network access controls which IPs/VNets can access Key Vault
  # Network access: public by default (can be restricted via network_acls if needed)
  network_acls {
    default_action = var.key_vault_network_default_action  # Default action (from variables.tf, default: "Allow")
    bypass         = "AzureServices"  # Bypass network rules for Azure services (required for AKS)
  }

  # Enable RBAC mode (recommended over access policies)
  # RBAC mode uses Azure RBAC for Key Vault access (more secure and flexible than access policies)
  enable_rbac_authorization = true  # Enable RBAC mode (recommended for security)

  tags = merge(var.tags, {
    Purpose = "RocketChatSecrets"  # Purpose tag (for resource organization)
  })
}

# Grant ESO identity "Key Vault Secrets User" role (read secrets)
# This role assignment allows External Secrets Operator to read secrets from Key Vault.
# ESO uses this UAMI to authenticate to Key Vault via Azure Workload Identity.
resource "azurerm_role_assignment" "eso_secrets_user" {
  scope                = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (scope for role assignment)
  role_definition_name = "Key Vault Secrets User"  # Azure RBAC role (allows reading secrets)
  principal_id         = azurerm_user_assigned_identity.eso.principal_id  # UAMI principal ID (ESO identity)
}

# Grant the current Terraform runner permission to manage Key Vault secrets.
# This role assignment allows Terraform to create/update/delete secrets in Key Vault.
# Required because Key Vault is in RBAC mode and the provider performs GetSecret/SetSecret calls.
resource "azurerm_role_assignment" "terraform_runner_secrets_officer" {
  scope                = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (scope for role assignment)
  role_definition_name = "Key Vault Secrets Officer"  # Azure RBAC role (allows managing secrets)
  principal_id         = data.azurerm_client_config.current.object_id  # Current Terraform runner's object ID
}

# Optional: Grant ESO identity "Key Vault Secrets Officer" if you want ESO to also create/update secrets
# By default, ESO only reads secrets from Key Vault (via "Key Vault Secrets User" role).
# Uncomment this if you want ESO to also create/update secrets (full lifecycle management).
# Uncomment if you want ESO to manage secret lifecycle (not just read)
# resource "azurerm_role_assignment" "eso_secrets_officer" {
#   scope                = azurerm_key_vault.rocketchat.id
#   role_definition_name = "Key Vault Secrets Officer"  # Azure RBAC role (allows managing secrets)
#   principal_id         = azurerm_user_assigned_identity.eso.principal_id  # UAMI principal ID (ESO identity)
# }

# Key Vault Secrets: Rocket.Chat secrets stored in Azure Key Vault
# These secrets are created from values in terraform.tfvars (gitignored for security).
# Key Vault Secrets (values from terraform.tfvars - gitignored)
# Note: data.azurerm_client_config.current is defined in aks.tf and can be referenced here
# These secrets are referenced by ExternalSecrets in ops/secrets/*.yaml
# See terraform/README.md for terraform.tfvars setup instructions.

# MongoDB connection URI: Rocket.Chat primary database connection
resource "azurerm_key_vault_secret" "rocketchat_mongo_uri" {
  name         = "rocketchat-mongo-uri"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-rocketchat-mongodb-external.yaml)
  value        = var.rocketchat_mongo_uri  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "RocketChatMongoConnection"  # Purpose tag (for resource organization)
  })
}

# MongoDB oplog connection URI: Rocket.Chat oplog database connection (for real-time features)
resource "azurerm_key_vault_secret" "rocketchat_mongo_oplog_uri" {
  name         = "rocketchat-mongo-oplog-uri"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-rocketchat-mongodb-external.yaml)
  value        = var.rocketchat_mongo_oplog_uri  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "RocketChatMongoOplogConnection"  # Purpose tag (for resource organization)
  })
}

# MongoDB admin password: MongoDB admin user password (for MongoDB Community Operator)
resource "azurerm_key_vault_secret" "mongodb_admin_password" {
  name         = "rocketchat-mongodb-admin-password"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-mongodb-admin-password.yaml)
  value        = var.mongodb_admin_password  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "MongoDBAdminPassword"  # Purpose tag (for resource organization)
  })
}

# MongoDB rocketchat user password: MongoDB rocketchat user password (for MongoDB Community Operator)
resource "azurerm_key_vault_secret" "mongodb_rocketchat_password" {
  name         = "rocketchat-mongodb-rocketchat-password"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-mongodb-rocketchat-password.yaml)
  value        = var.mongodb_rocketchat_password  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "MongoDBRocketChatPassword"  # Purpose tag (for resource organization)
  })
}

# MongoDB metrics endpoint password: MongoDB metrics endpoint password (for Prometheus scraping)
resource "azurerm_key_vault_secret" "mongodb_metrics_endpoint_password" {
  name         = "rocketchat-mongodb-metrics-endpoint-password"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-metrics-endpoint-password.yaml)
  value        = var.mongodb_metrics_endpoint_password  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "MongoDBMetricsPassword"  # Purpose tag (for resource organization)
  })
}

# Observability credentials: Username for basic auth to central observability hub (Grafana/Mimir/Tempo/Loki)
# This credential is used by Prometheus Agent, OTel Collector, and Promtail for authenticating to the hub.
resource "azurerm_key_vault_secret" "observability_username" {
  name         = "rocketchat-observability-username"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-observability-credentials.yaml)
  value        = var.observability_username  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "ObservabilityCredentials"  # Purpose tag (for resource organization)
  })
}

# Observability credentials: Password for basic auth to central observability hub (Grafana/Mimir/Tempo/Loki)
# This credential is used by Prometheus Agent, OTel Collector, and Promtail for authenticating to the hub.
resource "azurerm_key_vault_secret" "observability_password" {
  name         = "rocketchat-observability-password"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-observability-credentials.yaml)
  value        = var.observability_password  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "ObservabilityCredentials"  # Purpose tag (for resource organization)
  })
}

# Jenkins credentials: Admin username for Jenkins login
# This credential is used by Jenkins controller for admin authentication.
resource "azurerm_key_vault_secret" "jenkins_admin_username" {
  name         = "jenkins-admin-username"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-jenkins.yaml)
  value        = var.jenkins_admin_username  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "JenkinsCredentials"  # Purpose tag (for resource organization)
  })
}

# Jenkins credentials: Admin password for Jenkins login
# This credential is used by Jenkins controller for admin authentication.
resource "azurerm_key_vault_secret" "jenkins_admin_password" {
  name         = "jenkins-admin-password"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-jenkins.yaml)
  value        = var.jenkins_admin_password  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "JenkinsCredentials"  # Purpose tag (for resource organization)
  })
}

# Jenkins credentials: GitHub personal access token for PR validation
# This credential is used by Jenkins GitHub plugin for PR validation and webhook management.
resource "azurerm_key_vault_secret" "jenkins_github_token" {
  name         = "jenkins-github-token"  # Secret name (referenced by ExternalSecret in ops/secrets/externalsecret-jenkins.yaml)
  value        = var.jenkins_github_token  # Secret value (from terraform.tfvars, sensitive - never committed)
  key_vault_id = azurerm_key_vault.rocketchat.id  # Key Vault resource ID (from Key Vault resource above)
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]  # Wait for RBAC role assignment (required for RBAC mode)

  tags = merge(var.tags, {
    Purpose = "JenkinsCredentials"  # Purpose tag (for resource organization)
  })
}
