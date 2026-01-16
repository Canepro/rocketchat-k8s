# Azure Automation for AKS scheduled start/stop (cost optimization)
# This stops the cluster during off-peak hours and weekends

resource "azurerm_automation_account" "aks" {
  count               = var.enable_auto_shutdown ? 1 : 0
  name                = "aa-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Grant Automation Account permission to manage AKS (start/stop cluster)
resource "azurerm_role_assignment" "automation_aks_contributor" {
  count                = var.enable_auto_shutdown ? 1 : 0
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Contributor"  # Standard role for AKS cluster management (start/stop)
  principal_id         = azurerm_automation_account.aks[0].identity[0].principal_id
}

# Runbook to stop AKS cluster
resource "azurerm_automation_runbook" "stop_aks" {
  count                   = var.enable_auto_shutdown ? 1 : 0
  name                    = "Stop-AKS-Cluster"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.aks[0].name
  log_verbose             = false
  log_progress            = false
  runbook_type            = "PowerShell"

  content = <<-POWERSHELL
    # Stop AKS Cluster Runbook
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$ClusterName
    )

    # Connect using Managed Identity
    Connect-AzAccount -Identity

    Write-Output "Stopping AKS cluster $ClusterName in resource group $ResourceGroupName..."
    Stop-AzAksCluster -ResourceGroupName $ResourceGroupName -Name $ClusterName
    Write-Output "AKS cluster stopped successfully."
  POWERSHELL

  tags = var.tags
}

# Runbook to start AKS cluster
resource "azurerm_automation_runbook" "start_aks" {
  count                   = var.enable_auto_shutdown ? 1 : 0
  name                    = "Start-AKS-Cluster"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.aks[0].name
  log_verbose             = false
  log_progress            = false
  runbook_type            = "PowerShell"

  content = <<-POWERSHELL
    # Start AKS Cluster Runbook
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$ClusterName
    )

    # Connect using Managed Identity
    Connect-AzAccount -Identity

    Write-Output "Starting AKS cluster $ClusterName in resource group $ResourceGroupName..."
    Start-AzAksCluster -ResourceGroupName $ResourceGroupName -Name $ClusterName
    Write-Output "AKS cluster started successfully."
  POWERSHELL

  tags = var.tags
}

# Local to compute schedule start times
locals {
  # Use a date far enough in the future to avoid "start_time must be in future" errors
  schedule_base_date = formatdate("YYYY-MM-DD", timeadd(timestamp(), "24h"))
  shutdown_start     = "${local.schedule_base_date}T${var.shutdown_time}:00Z"
  startup_start      = "${local.schedule_base_date}T${var.startup_time}:00Z"
}

# Schedule: Stop cluster in the evening on weekdays
resource "azurerm_automation_schedule" "stop_weekday_evening" {
  count                   = var.enable_auto_shutdown ? 1 : 0
  name                    = "stop-aks-weekday-evening"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.aks[0].name
  frequency               = "Week"
  interval                = 1
  timezone                = var.shutdown_timezone
  start_time              = local.shutdown_start
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Schedule: Start cluster in the morning on weekdays only (stays off weekends)
resource "azurerm_automation_schedule" "start_weekday_morning" {
  count                   = var.enable_auto_shutdown ? 1 : 0
  name                    = "start-aks-weekday-morning"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.aks[0].name
  frequency               = "Week"
  interval                = 1
  timezone                = var.shutdown_timezone
  start_time              = local.startup_start
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Link stop runbook to weekday evening schedule
resource "azurerm_automation_job_schedule" "stop_weekday" {
  count                   = var.enable_auto_shutdown ? 1 : 0
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.aks[0].name
  schedule_name           = azurerm_automation_schedule.stop_weekday_evening[0].name
  runbook_name            = azurerm_automation_runbook.stop_aks[0].name

  parameters = {
    resourcegroupname = azurerm_resource_group.main.name
    clustername       = azurerm_kubernetes_cluster.main.name
  }
}

# Link start runbook to weekday morning schedule
resource "azurerm_automation_job_schedule" "start_weekday" {
  count                   = var.enable_auto_shutdown ? 1 : 0
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.aks[0].name
  schedule_name           = azurerm_automation_schedule.start_weekday_morning[0].name
  runbook_name            = azurerm_automation_runbook.start_aks[0].name

  parameters = {
    resourcegroupname = azurerm_resource_group.main.name
    clustername       = azurerm_kubernetes_cluster.main.name
  }
}

# Output for manual control
output "aks_manual_start_command" {
  description = "Command to manually start the AKS cluster"
  value       = "az aks start --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "aks_manual_stop_command" {
  description = "Command to manually stop the AKS cluster"
  value       = "az aks stop --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}
