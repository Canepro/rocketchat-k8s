# Terraform Configuration: Budget guardrails for the personal Azure subscription.
# This creates a subscription-level monthly budget and an Action Group email receiver.

locals {
  personal_subscription_resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

resource "azurerm_monitor_action_group" "budget" {
  name                = "${var.cluster_name}-budget-ag"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "aksbudget"

  email_receiver {
    name          = "primary-budget-email"
    email_address = var.budget_alert_email
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
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 50
    threshold_type = "Actual"
    contact_emails = [var.budget_alert_email]
    contact_groups = [azurerm_monitor_action_group.budget.id]
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 80
    threshold_type = "Actual"
    contact_emails = [var.budget_alert_email]
    contact_groups = [azurerm_monitor_action_group.budget.id]
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 100
    threshold_type = "Actual"
    contact_emails = [var.budget_alert_email]
    contact_groups = [azurerm_monitor_action_group.budget.id]
  }
}
