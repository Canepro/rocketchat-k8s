# Terraform Configuration: Azure Automation for AKS Scheduled Start/Stop
# This file provisions Azure Automation resources for scheduled AKS cluster start/stop (cost optimization).
# It includes: Automation Account, Runbooks (start/stop), Schedules (weekday evenings/mornings), and Job Schedules.
# Azure Automation for AKS scheduled start/stop (cost optimization)
# This stops the cluster during off-peak hours and weekends
# See variables.tf for schedule configuration (shutdown_time, startup_time, shutdown_timezone).

# Azure Automation Account: Container for Runbooks and Schedules
# This Automation Account runs PowerShell runbooks to start/stop the AKS cluster.
resource "azurerm_automation_account" "aks" {
  count               = var.enable_auto_shutdown ? 1 : 0  # Only create if auto-shutdown is enabled
  name                = "aa-${var.cluster_name}"  # Automation Account name (from variables.tf, e.g., "aa-aks-canepro")
  location            = azurerm_resource_group.main.location  # Azure region (from resource group)
  resource_group_name = azurerm_resource_group.main.name  # Resource group (from main.tf)
  sku_name            = "Basic"  # Automation Account SKU (Basic = free tier, sufficient for simple runbooks)

  identity {
    type = "SystemAssigned"  # System-Assigned Managed Identity (for AKS start/stop permissions)
  }

  tags = var.tags  # Tags for Automation Account (from variables.tf)
}

# Grant Automation Account permission to manage AKS (start/stop cluster)
# This role assignment allows the Automation Account to start/stop the AKS cluster via Azure PowerShell cmdlets.
resource "azurerm_role_assignment" "automation_aks_contributor" {
  count                = var.enable_auto_shutdown ? 1 : 0  # Only create if auto-shutdown is enabled
  scope                = azurerm_kubernetes_cluster.main.id  # AKS cluster resource ID (scope for role assignment)
  role_definition_name = "Contributor"  # Standard role for AKS cluster management (start/stop)
  principal_id         = azurerm_automation_account.aks[0].identity[0].principal_id  # Automation Account's Managed Identity principal ID
}

# Runbook to stop AKS cluster: PowerShell script to stop the AKS cluster
# Runbook to stop AKS cluster
resource "azurerm_automation_runbook" "stop_aks" {
  count                   = var.enable_auto_shutdown ? 1 : 0  # Only create if auto-shutdown is enabled
  name                    = "Stop-AKS-Cluster"  # Runbook name (for identification in Azure Portal)
  location                = azurerm_resource_group.main.location  # Azure region (from resource group)
  resource_group_name     = azurerm_resource_group.main.name  # Resource group (from main.tf)
  automation_account_name = azurerm_automation_account.aks[0].name  # Automation Account name (from Automation Account resource above)
  log_verbose             = false  # Disable verbose logging (reduces log volume)
  log_progress            = false  # Disable progress logging (reduces log volume)
  runbook_type            = "PowerShell"  # Runbook type (PowerShell for Azure PowerShell cmdlets)

  content = <<-POWERSHELL
    # Stop AKS Cluster Runbook
    # This runbook stops the AKS cluster to save costs during off-peak hours.
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,  # Resource group name (passed from Job Schedule)
        
        [Parameter(Mandatory=$true)]
        [string]$ClusterName  # Cluster name (passed from Job Schedule)
    )

    # Use the current subscription id from Terraform runner
    $SubscriptionId = "${data.azurerm_client_config.current.subscription_id}"

    Write-Output "Authenticating to Azure with System-Assigned Managed Identity..."
    try {
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Aks -ErrorAction Stop

        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error ("Auth/context failed: " + $_.Exception.Message)
        throw
    }

    Write-Output "Stopping AKS cluster $ClusterName in resource group $ResourceGroupName..."
    Stop-AzAksCluster -ResourceGroupName $ResourceGroupName -Name $ClusterName -ErrorAction Stop  # Stop AKS cluster
    Write-Output "AKS cluster stopped successfully."
  POWERSHELL

  tags = var.tags  # Tags for Runbook (from variables.tf)
}

# Runbook to start AKS cluster: PowerShell script to start the AKS cluster
# Runbook to start AKS cluster
resource "azurerm_automation_runbook" "start_aks" {
  count                   = var.enable_auto_shutdown ? 1 : 0  # Only create if auto-shutdown is enabled
  name                    = "Start-AKS-Cluster"  # Runbook name (for identification in Azure Portal)
  location                = azurerm_resource_group.main.location  # Azure region (from resource group)
  resource_group_name     = azurerm_resource_group.main.name  # Resource group (from main.tf)
  automation_account_name = azurerm_automation_account.aks[0].name  # Automation Account name (from Automation Account resource above)
  log_verbose             = false  # Disable verbose logging (reduces log volume)
  log_progress            = false  # Disable progress logging (reduces log volume)
  runbook_type            = "PowerShell"  # Runbook type (PowerShell for Azure PowerShell cmdlets)

  content = <<-POWERSHELL
    # Start AKS Cluster Runbook
    # This runbook starts the AKS cluster for weekday mornings.
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,  # Resource group name (passed from Job Schedule)
        
        [Parameter(Mandatory=$true)]
        [string]$ClusterName  # Cluster name (passed from Job Schedule)
    )

    # Use the current subscription id from Terraform runner
    $SubscriptionId = "${data.azurerm_client_config.current.subscription_id}"

    Write-Output "Authenticating to Azure with System-Assigned Managed Identity..."
    try {
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Aks -ErrorAction Stop

        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error ("Auth/context failed: " + $_.Exception.Message)
        throw
    }

    Write-Output "Starting AKS cluster $ClusterName in resource group $ResourceGroupName..."
    Start-AzAksCluster -ResourceGroupName $ResourceGroupName -Name $ClusterName -ErrorAction Stop  # Start AKS cluster
    Write-Output "AKS cluster started successfully."
  POWERSHELL

  tags = var.tags  # Tags for Runbook (from variables.tf)
}

# Local values: Compute schedule start times
# Local to compute schedule start times
locals {
  # Use a date far enough in the future to avoid "start_time must be in future" errors
  # Azure Automation schedules require start_time to be in the future (at least 5 minutes from now)
  schedule_base_date = formatdate("YYYY-MM-DD", timeadd(timestamp(), "24h"))  # Tomorrow's date (ensures future date)
  shutdown_start     = "${local.schedule_base_date}T${var.shutdown_time}:00Z"  # Shutdown time (from variables.tf, default: "20:00")
  startup_start      = "${local.schedule_base_date}T${var.startup_time}:00Z"  # Startup time (from variables.tf, default: "07:00")
}

# Schedule: Stop cluster in the evening on weekdays
# This schedule runs the stop runbook every weekday evening at the configured time.
# Schedule: Stop cluster in the evening on weekdays
resource "azurerm_automation_schedule" "stop_weekday_evening" {
  count                   = var.enable_auto_shutdown ? 1 : 0  # Only create if auto-shutdown is enabled
  name                    = "stop-aks-weekday-evening"  # Schedule name (for identification in Azure Portal)
  resource_group_name     = azurerm_resource_group.main.name  # Resource group (from main.tf)
  automation_account_name = azurerm_automation_account.aks[0].name  # Automation Account name (from Automation Account resource above)
  frequency               = "Week"  # Schedule frequency (Week = weekly schedule)
  interval                = 1  # Schedule interval (1 = every week)
  timezone                = var.shutdown_timezone  # Timezone for schedule (from variables.tf, default: "GMT Standard Time")
  start_time              = local.shutdown_start  # Schedule start time (from local values, default: tomorrow 20:00 UTC)
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]  # Weekdays only (excludes weekends)

  lifecycle {
    # Ignore start_time changes (prevents Terraform from updating schedule time on every apply)
    ignore_changes = [start_time]  # Schedule start_time is managed by Automation Account (not Terraform)
  }
}

# Schedule: Start cluster in the morning on weekdays only (stays off weekends)
# This schedule runs the start runbook every weekday morning at the configured time.
# Cluster stays off on weekends (no schedule on Saturday/Sunday).
# Schedule: Start cluster in the morning on weekdays only (stays off weekends)
resource "azurerm_automation_schedule" "start_weekday_morning" {
  count                   = var.enable_auto_shutdown ? 1 : 0  # Only create if auto-shutdown is enabled
  name                    = "start-aks-weekday-morning"  # Schedule name (for identification in Azure Portal)
  resource_group_name     = azurerm_resource_group.main.name  # Resource group (from main.tf)
  automation_account_name = azurerm_automation_account.aks[0].name  # Automation Account name (from Automation Account resource above)
  frequency               = "Week"  # Schedule frequency (Week = weekly schedule)
  interval                = 1  # Schedule interval (1 = every week)
  timezone                = var.shutdown_timezone  # Timezone for schedule (from variables.tf, default: "GMT Standard Time")
  start_time              = local.startup_start  # Schedule start time (from local values, default: tomorrow 07:00 UTC)
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]  # Weekdays only (excludes weekends)

  lifecycle {
    # Ignore start_time changes (prevents Terraform from updating schedule time on every apply)
    ignore_changes = [start_time]  # Schedule start_time is managed by Automation Account (not Terraform)
  }
}

# Link stop runbook to weekday evening schedule: Connect Runbook to Schedule
# This Job Schedule links the stop runbook to the weekday evening schedule.
# Link stop runbook to weekday evening schedule
resource "azurerm_automation_job_schedule" "stop_weekday" {
  count                   = var.enable_auto_shutdown ? 1 : 0  # Only create if auto-shutdown is enabled
  resource_group_name     = azurerm_resource_group.main.name  # Resource group (from main.tf)
  automation_account_name = azurerm_automation_account.aks[0].name  # Automation Account name (from Automation Account resource above)
  schedule_name           = azurerm_automation_schedule.stop_weekday_evening[0].name  # Schedule name (from schedule resource above)
  runbook_name            = azurerm_automation_runbook.stop_aks[0].name  # Runbook name (from runbook resource above)

  parameters = {
    # Runbook parameters: Passed to runbook when schedule triggers it
    resourcegroupname = azurerm_resource_group.main.name  # Resource group name (for Stop-AzAksCluster cmdlet)
    clustername       = azurerm_kubernetes_cluster.main.name  # Cluster name (for Stop-AzAksCluster cmdlet)
  }
}

# Link start runbook to weekday morning schedule: Connect Runbook to Schedule
# This Job Schedule links the start runbook to the weekday morning schedule.
# Link start runbook to weekday morning schedule
resource "azurerm_automation_job_schedule" "start_weekday" {
  count                   = var.enable_auto_shutdown ? 1 : 0  # Only create if auto-shutdown is enabled
  resource_group_name     = azurerm_resource_group.main.name  # Resource group (from main.tf)
  automation_account_name = azurerm_automation_account.aks[0].name  # Automation Account name (from Automation Account resource above)
  schedule_name           = azurerm_automation_schedule.start_weekday_morning[0].name  # Schedule name (from schedule resource above)
  runbook_name            = azurerm_automation_runbook.start_aks[0].name  # Runbook name (from runbook resource above)

  parameters = {
    # Runbook parameters: Passed to runbook when schedule triggers it
    resourcegroupname = azurerm_resource_group.main.name  # Resource group name (for Start-AzAksCluster cmdlet)
    clustername       = azurerm_kubernetes_cluster.main.name  # Cluster name (for Start-AzAksCluster cmdlet)
  }
}

# Manual Control Outputs: Commands for manual cluster start/stop
# These outputs provide Azure CLI commands for manually starting/stopping the cluster.
# Output for manual control
output "aks_manual_start_command" {
  description = "Command to manually start the AKS cluster"  # Azure CLI command for manual cluster start
  value       = "az aks start --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"  # Azure CLI command
}

output "aks_manual_stop_command" {
  description = "Command to manually stop the AKS cluster"  # Azure CLI command for manual cluster stop
  value       = "az aks stop --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"  # Azure CLI command
}
