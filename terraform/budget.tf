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

  dynamic "automation_runbook_receiver" {
    for_each = var.enable_auto_shutdown ? [1] : []

    content {
      name                    = "mtd-cost-breakdown"
      automation_account_id   = azurerm_automation_account.aks[0].id
      runbook_name            = azurerm_automation_runbook.cost_breakdown[0].name
      webhook_resource_id     = azurerm_automation_webhook.cost_breakdown[0].id
      service_uri             = azurerm_automation_webhook.cost_breakdown[0].uri
      is_global_runbook       = false
      use_common_alert_schema = false
    }
  }

  tags = merge(var.tags, {
    Purpose = "BudgetAlerts"
  })
}

# A budget notification needs subscription-wide cost visibility so the breakdown
# can group all current charges by resource group and service. This role is read-only.
resource "azurerm_role_assignment" "automation_cost_management_reader" {
  count                = var.enable_auto_shutdown ? 1 : 0
  scope                = local.personal_subscription_resource_id
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_automation_account.aks[0].identity[0].principal_id
}

resource "azurerm_automation_runbook" "cost_breakdown" {
  count                   = var.enable_auto_shutdown ? 1 : 0
  name                    = "Report-MTD-Cost-Breakdown"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.aks[0].name
  log_verbose             = false
  log_progress            = false
  runbook_type            = "PowerShell"

  content = <<-POWERSHELL
    param(
        [Parameter(Mandatory=$false)]
        [object]$WebhookData
    )

    $ErrorActionPreference = "Stop"
    $SubscriptionId = "${data.azurerm_client_config.current.subscription_id}"
    $CostQueryUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-11-01"

    Import-Module Az.Accounts -ErrorAction Stop
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

    $Payload = @{
        type      = "ActualCost"
        timeframe = "MonthToDate"
        dataset   = @{
            granularity = "None"
            aggregation = @{
                totalCost = @{
                    name     = "Cost"
                    function = "Sum"
                }
            }
            grouping = @(
                @{
                    type = "Dimension"
                    name = "ResourceGroupName"
                },
                @{
                    type = "Dimension"
                    name = "ServiceName"
                }
            )
        }
    } | ConvertTo-Json -Depth 8 -Compress

    $Rows = @()
    $NextUri = $CostQueryUri

    while ($NextUri) {
        $Attempt = 0
        do {
            $Attempt++
            try {
                $PageResponse = Invoke-AzRestMethod -Method Post -Uri $NextUri -Payload $Payload -ErrorAction Stop
                $Page = $PageResponse.Content | ConvertFrom-Json -ErrorAction Stop
                $Complete = $true
            }
            catch {
                $Complete = $false
                $StatusCode = [int]$_.Exception.Response.StatusCode
                if ($StatusCode -ne 429 -or $Attempt -ge 3) {
                    throw
                }

                $RetryAfter = 5
                foreach ($HeaderName in @(
                    "x-ms-ratelimit-microsoft.costmanagement-qpu-retry-after",
                    "x-ms-ratelimit-microsoft.costmanagement-entity-retry-after",
                    "x-ms-ratelimit-microsoft.costmanagement-tenant-retry-after",
                    "Retry-After"
                )) {
                    $HeaderValues = $null
                    if ($_.Exception.Response.Headers.TryGetValues($HeaderName, [ref]$HeaderValues)) {
                        foreach ($HeaderValue in $HeaderValues) {
                            $ParsedRetryAfter = 0
                            if ([int]::TryParse($HeaderValue, [ref]$ParsedRetryAfter)) {
                                $RetryAfter = [Math]::Max($RetryAfter, $ParsedRetryAfter)
                            }
                        }
                    }
                }

                Write-Output "Cost query rate limited; retrying after $RetryAfter seconds."
                Start-Sleep -Seconds $RetryAfter
            }
        } until ($Complete)

        $Rows += @($Page.properties.rows)
        $Columns = @($Page.properties.columns | ForEach-Object { $_.name })
        $NextUri = [string]$Page.properties.nextLink
    }

    $CostIndex = [Array]::IndexOf($Columns, "Cost")
    $ResourceGroupIndex = [Array]::IndexOf($Columns, "ResourceGroupName")
    $ServiceIndex = [Array]::IndexOf($Columns, "ServiceName")
    $CurrencyIndex = [Array]::IndexOf($Columns, "Currency")

    if ($CostIndex -lt 0 -or $ResourceGroupIndex -lt 0 -or $ServiceIndex -lt 0 -or $CurrencyIndex -lt 0) {
        throw "Cost Management returned an unexpected column set."
    }

    $TotalCost = 0.0
    $Breakdown = @(
        foreach ($Row in $Rows) {
            $Cost = [double]$Row[$CostIndex]
            $TotalCost += $Cost
            $ResourceGroup = [string]$Row[$ResourceGroupIndex]
            if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
                $ResourceGroup = "unassigned"
            }

            [ordered]@{
                resourceGroup = $ResourceGroup
                service       = [string]$Row[$ServiceIndex]
                cost          = [Math]::Round($Cost, 6)
                currency      = [string]$Row[$CurrencyIndex]
            }
        }
    )

    $Output = [ordered]@{
        schema         = "canepro.azure.cost.mtd.v1"
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        trigger        = if ($null -ne $WebhookData) { "budget-action-group" } else { "manual" }
        timeframe      = "MonthToDate"
        totalCost      = [Math]::Round($TotalCost, 6)
        rowCount       = $Breakdown.Count
        breakdown      = @($Breakdown | Sort-Object -Property @{ Expression = { $_.cost }; Descending = $true })
    }

    $Output | ConvertTo-Json -Depth 6 -Compress | Write-Output
  POWERSHELL

  tags = merge(var.tags, {
    Purpose = "BudgetCostBreakdown"
  })

  depends_on = [azurerm_role_assignment.automation_cost_management_reader]
}

resource "time_static" "cost_breakdown_webhook_anchor" {
  count = var.enable_auto_shutdown ? 1 : 0
}

resource "azurerm_automation_webhook" "cost_breakdown" {
  count                   = var.enable_auto_shutdown ? 1 : 0
  name                    = "budget-mtd-cost-breakdown"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.aks[0].name
  runbook_name            = azurerm_automation_runbook.cost_breakdown[0].name
  expiry_time             = timeadd(time_static.cost_breakdown_webhook_anchor[0].rfc3339, "43800h")
  enabled                 = true
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
