# Azure Key Vault for GitOps secrets management (External Secrets Operator)
# This provisions the Key Vault infrastructure AND secret values (from terraform.tfvars)

# User Assigned Managed Identity for External Secrets Operator
resource "azurerm_user_assigned_identity" "eso" {
  name                = "${var.cluster_name}-eso-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    Purpose = "ExternalSecretsOperator"
  })
}

# Azure Key Vault
resource "azurerm_key_vault" "rocketchat" {
  name                       = "${var.cluster_name}-kv-${substr(md5(azurerm_resource_group.main.id), 0, 6)}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = 7
  purge_protection_enabled   = var.key_vault_purge_protection

  # Network access: public by default (can be restricted via network_acls if needed)
  network_acls {
    default_action = var.key_vault_network_default_action
    bypass         = "AzureServices"
  }

  # Enable RBAC mode (recommended over access policies)
  enable_rbac_authorization = true

  tags = merge(var.tags, {
    Purpose = "RocketChatSecrets"
  })
}

# Grant ESO identity "Key Vault Secrets User" role (read secrets)
resource "azurerm_role_assignment" "eso_secrets_user" {
  scope                = azurerm_key_vault.rocketchat.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.eso.principal_id
}

# Grant the current Terraform runner permission to manage Key Vault secrets.
# Required because Key Vault is in RBAC mode and the provider performs GetSecret/SetSecret calls.
resource "azurerm_role_assignment" "terraform_runner_secrets_officer" {
  scope                = azurerm_key_vault.rocketchat.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Optional: Grant ESO identity "Key Vault Secrets Officer" if you want ESO to also create/update secrets
# Uncomment if you want ESO to manage secret lifecycle (not just read)
# resource "azurerm_role_assignment" "eso_secrets_officer" {
#   scope                = azurerm_key_vault.rocketchat.id
#   role_definition_name = "Key Vault Secrets Officer"
#   principal_id         = azurerm_user_assigned_identity.eso.principal_id
# }

# Key Vault Secrets (values from terraform.tfvars - gitignored)
# Note: data.azurerm_client_config.current is defined in aks.tf and can be referenced here
# These secrets are referenced by ExternalSecrets in ops/secrets/*.yaml

resource "azurerm_key_vault_secret" "rocketchat_mongo_uri" {
  name         = "rocketchat-mongo-uri"
  value        = var.rocketchat_mongo_uri
  key_vault_id = azurerm_key_vault.rocketchat.id
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]

  tags = merge(var.tags, {
    Purpose = "RocketChatMongoConnection"
  })
}

resource "azurerm_key_vault_secret" "rocketchat_mongo_oplog_uri" {
  name         = "rocketchat-mongo-oplog-uri"
  value        = var.rocketchat_mongo_oplog_uri
  key_vault_id = azurerm_key_vault.rocketchat.id
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]

  tags = merge(var.tags, {
    Purpose = "RocketChatMongoOplogConnection"
  })
}

resource "azurerm_key_vault_secret" "mongodb_admin_password" {
  name         = "rocketchat-mongodb-admin-password"
  value        = var.mongodb_admin_password
  key_vault_id = azurerm_key_vault.rocketchat.id
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]

  tags = merge(var.tags, {
    Purpose = "MongoDBAdminPassword"
  })
}

resource "azurerm_key_vault_secret" "mongodb_rocketchat_password" {
  name         = "rocketchat-mongodb-rocketchat-password"
  value        = var.mongodb_rocketchat_password
  key_vault_id = azurerm_key_vault.rocketchat.id
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]

  tags = merge(var.tags, {
    Purpose = "MongoDBRocketChatPassword"
  })
}

resource "azurerm_key_vault_secret" "mongodb_metrics_endpoint_password" {
  name         = "rocketchat-mongodb-metrics-endpoint-password"
  value        = var.mongodb_metrics_endpoint_password
  key_vault_id = azurerm_key_vault.rocketchat.id
  depends_on   = [azurerm_role_assignment.terraform_runner_secrets_officer]

  tags = merge(var.tags, {
    Purpose = "MongoDBMetricsPassword"
  })
}
