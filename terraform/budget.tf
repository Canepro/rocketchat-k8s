# Terraform Configuration: Budget guardrails for the personal Azure subscription.
# This creates a subscription-level monthly budget and an Action Group email receiver.

locals {
  personal_subscription_resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  # Azure monthly budgets reject recreated resources when the configured start date is
  # before the current month. Derive a valid month boundary for creates, then let
  # lifecycle ignore_changes keep existing budgets stable across later months.
  budget_start_of_current_month = "${formatdate("YYYY-MM", timestamp())}-01T00:00:00Z"
  # CI can validate with placeholder tfvars or an empty Jenkins secret; normalize that
  # to a non-empty placeholder so `terraform plan` stays deterministic.
  budget_alert_email_effective = trimspace(var.budget_alert_email) != "" ? trimspace(var.budget_alert_email) : "REPLACE_ME@example.com"
}

resource "azurerm_monitor_action_group" "budget" {
  name                = "${var.cluster_name}-budget-ag"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "aksbudget"

  email_receiver {
    name          = "primary-budget-email"
    email_address = local.budget_alert_email_effective
  }

  tags = merge(var.tags, {
    Purpose = "BudgetAlerts"
  })
}

resource "azurerm_consumption_budget_subscription" "personal" {
  name            = "${var.cluster_name}-monthly-budget"
  subscription_id = local.personal_subscription_resource_id
  amount          = var.monthly_budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date != "" ? var.budget_start_date : local.budget_start_of_current_month
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 50
    threshold_type = "Actual"
    contact_emails = []
    contact_groups = [azurerm_monitor_action_group.budget.id]
    contact_roles  = []
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 80
    threshold_type = "Actual"
    contact_emails = []
    contact_groups = [azurerm_monitor_action_group.budget.id]
    contact_roles  = []
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 100
    threshold_type = "Actual"
    contact_emails = []
    contact_groups = [azurerm_monitor_action_group.budget.id]
    contact_roles  = []
  }

  lifecycle {
    ignore_changes = [
      # Keep recreated budgets valid without forcing monthly replacements once created.
      time_period[0].start_date,
    ]
  }
}
