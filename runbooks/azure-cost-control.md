# Azure cost-control operations

Stage 1 cost control is deployed from commit
`1f9256ae2c81503fa36b519caa621696e97ff635`. It adds a read-only
month-to-date cost report to the existing budget-alert path and makes scheduled
AKS stops return early when the cluster is already stopped.

Stage 1 does not perform cost-based remediation. A budget alert does not stop,
delete, resize, or recreate any Azure or Kubernetes resource.

## Budget alert to cost breakdown

The Terraform-managed path is:

1. Subscription budget `aks-canepro-monthly-budget` reaches an actual-cost
   threshold of 50, 80, or 100 percent.
2. Action group `aks-canepro-budget-ag` keeps the `primary-budget-email`
   receiver and also invokes the `mtd-cost-breakdown` Automation receiver.
3. Webhook `budget-mtd-cost-breakdown` starts the published
   `Report-MTD-Cost-Breakdown` runbook in Automation account
   `aa-aks-canepro`.
4. The runbook queries subscription-wide `ActualCost` for `MonthToDate`, grouped
   by `ResourceGroupName` and `ServiceName`, then writes one JSON document to
   the Automation job output.

The email and runbook invocation are separate action-group receivers. The email
remains the immediate notification. Open the corresponding Automation job to
read the generated breakdown; the breakdown is not added to the email body.

The Automation account's system-assigned managed identity has `Cost Management
Reader` at subscription scope. This role lets the runbook query all current
subscription charges without granting cost-management writes or resource
mutation. The separate cluster-scoped `Contributor` assignment remains limited
in scope to the AKS resource and supports the existing start and stop runbooks.

The report follows pagination links and retries Cost Management HTTP 429
responses up to three attempts, using the longest returned retry interval.

## Cost report output contract

`Report-MTD-Cost-Breakdown` emits compact JSON with this contract:

```json
{
  "schema": "canepro.azure.cost.mtd.v1",
  "generatedAtUtc": "<ISO-8601 UTC timestamp>",
  "trigger": "budget-action-group",
  "timeframe": "MonthToDate",
  "totalCost": 51.253885,
  "rowCount": 19,
  "breakdown": [
    {
      "resourceGroup": "<resource group or unassigned>",
      "service": "<Azure service>",
      "cost": 0.0,
      "currency": "<billing currency>"
    }
  ]
}
```

- `trigger` is `budget-action-group` when Azure passes webhook data and `manual`
  when an operator starts the runbook without webhook data.
- `totalCost` and each row's `cost` are rounded to six decimal places.
- `breakdown` is sorted by `cost` from highest to lowest.
- A blank Azure resource-group value is normalized to `unassigned`.
- `rowCount` is the number of grouped cost rows, not the number of Azure
  resources.

Cost Management data can lag current resource activity. Treat the report as the
current billing-system view for the month, not as proof that a resource is
running now.

## Stopped-state no-op contract

`Stop-AKS-Cluster` authenticates, reads the AKS power state, and checks for
`Stopped` before it reads the Jenkins token or calls Jenkins. A stopped cluster
returns this compact JSON and exits successfully:

```json
{
  "schema": "canepro.aks.stop.v1",
  "result": "noop",
  "powerState": "Stopped",
  "resourceGroup": "rg-canepro-aks",
  "cluster": "aks-canepro"
}
```

If the cluster is running, the existing path still attempts the Jenkins
graceful disconnect, waits for the node to drain when credentials are present,
and then stops AKS. Jenkins disconnect failures remain non-fatal to the stop.

## Live verification recorded on 2026-07-19

- Commit `1f9256ae2c81503fa36b519caa621696e97ff635` was present on
  `origin/main`.
- Webhook smoke job `b951f71a-c3fd-4bd8-87d5-129200520e2d` completed with
  schema `canepro.azure.cost.mtd.v1`, trigger `budget-action-group`, MTD total
  `51.253885`, and 19 cost-sorted rows.
- Stop smoke job `b13e55b6-9a2c-4a76-9044-a9f9c42c8c8d` completed with schema
  `canepro.aks.stop.v1`, result `noop`, and power state `Stopped`.
- AKS remained `Stopped` with provisioning state `Succeeded`.
- Terraform format, validation, diff check, and a targeted live plan passed with
  no changes.
- No ACR, public IP, PVC, managed disk, or cluster deletion occurred. Nothing
  was resized.

These job IDs are point-in-time smoke evidence. Use the latest job and current
Terraform state during a later incident.

## Troubleshooting

### The email arrives but there is no cost-report job

1. Confirm the alert names `aks-canepro-monthly-budget`. `AKS_Budget` is the
   legacy pre-migration budget and does not prove this path ran.
2. In the `aks-canepro-budget-ag` action group, confirm both the email receiver
   and `mtd-cost-breakdown` Automation receiver are present.
3. Confirm `Report-MTD-Cost-Breakdown` is published and webhook
   `budget-mtd-cost-breakdown` is enabled and unexpired.
4. Run a Terraform plan and investigate drift before applying anything. Do not
   print or copy the webhook service URI; possession of that URI can invoke the
   runbook.

### The report job fails with authorization errors

Confirm the managed identity for `aa-aks-canepro` has `Cost Management Reader`
on the subscription that owns the budget. A resource-group-scoped assignment is
too narrow for the subscription query. After a new role assignment, allow for
Azure RBAC propagation before retrying.

### The report is empty, delayed, or has unexpected columns

- Check the Automation job exception and confirm the query still returns
  `Cost`, `ResourceGroupName`, `ServiceName`, and `Currency`.
- Confirm the timeframe is `MonthToDate` and the query type is `ActualCost`.
- Allow for Cost Management ingestion delay before treating a missing recent
  charge as a runbook fault.
- If all three rate-limit attempts fail, wait for the reported retry interval
  and start a manual read-only report job later.

### A scheduled stop touches Jenkins while AKS is stopped

Check that the active published `Stop-AKS-Cluster` revision includes the
power-state check from commit `1f9256ae2c81503fa36b519caa621696e97ff635`.
The expected stopped-state result is `canepro.aks.stop.v1` with `result: noop`.
Also confirm the live AKS state independently:

```bash
az aks show \
  --resource-group rg-canepro-aks \
  --name aks-canepro \
  --query '{powerState:powerState.code,provisioningState:provisioningState}' \
  --output json
```

Do not start AKS or run the weekly maintenance automation only to test this
branch. A stopped-state Automation job is the bounded smoke test.

## Destructive-action boundary

The cost report is observation only. A high-cost row is evidence for review,
not permission to modify the resource. Stage 1 does not delete ACR data, public
IPs, PVCs, managed disks, or the AKS cluster, and it does not resize disks or
compute.

Any deletion, resize, new cost-control action, role expansion, or change to the
AKS schedule requires its own reviewed Terraform or GitOps change and the
applicable approval. Preserve the stopped cluster and persistent resources while
investigating cost data unless a separately approved runbook says otherwise.
