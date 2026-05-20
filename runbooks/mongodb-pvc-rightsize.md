# MongoDB PVC right-size runbook

Use this when the personal PAYG AKS Rocket.Chat test cluster has stopped-cluster residual cost from MongoDB storage, especially the `data-volume-mongodb-0` disk.

## Ownership model

- **Azure Terraform owns** the AKS cluster, VNet, Key Vault, Automation, budget, and identity resources under `terraform/`.
- **ArgoCD runs on OKE** and deploys this repo into AKS. AKS is only the target cluster.
- **ArgoCD owns** the Kubernetes desired state for MongoDB through `aks-rocketchat-ops` and `ops/manifests/mongodb-community.yaml`.
- **AKS dynamic provisioning owns** the Azure managed disks created from Kubernetes PVCs. Do not add those PVC disks to Terraform.

Do not delete Azure disks directly from the managed resource group. Change GitOps intent, take a backup, and let Kubernetes/ArgoCD recreate resources during a controlled maintenance window.

## Current cost target

The expensive stopped-cluster disk is usually:

- PVC: `data-volume-mongodb-0`
- Namespace: `rocketchat`
- Azure disk tag: `kubernetes.io-created-for-pvc-name=data-volume-mongodb-0`
- Current manifest request: `50Gi`
- Current storage class: `managed-premium`

For occasional Rocket.Chat testing, prefer a smaller Standard SSD target once actual MongoDB data size is confirmed. A normal first target is `16Gi` with a Standard SSD-backed AKS storage class. Keep at least 2x the current MongoDB data size plus restore headroom.

## 2026-05-20 sizing check

Read-only AKS check after manual start:

- AKS was running Kubernetes `1.34.3`.
- OKE ArgoCD could see `aks-rocketchat-ops`, `aks-rocketchat-helm`, and `aks-rocketchat-secrets`.
- `data-volume-mongodb-0` was bound to a `50Gi` `managed-premium` PVC.
- `/data` filesystem usage was about `352MiB`.
- `du -sh /data` reported about `335MiB`.
- MongoDB `rocketchat` database logical `dataSize` was about `18MiB`.
- MongoDB `local` database logical `dataSize` was about `60MiB`.
- `mongodump` and `mongorestore` are present in the MongoDB container.

Recommendation from this check: use `16Gi` on `managed-csi` for a conservative first reduction. `8Gi` would probably work for the current data volume, but `16Gi` leaves more restore and test headroom for little operational complexity.

## Read-only discovery

Start AKS manually:

```bash
az aks start --resource-group rg-canepro-aks --name aks-canepro
```

Confirm power state:

```bash
az aks show \
  --resource-group rg-canepro-aks \
  --name aks-canepro \
  --query '{powerState:powerState.code,provisioningState:provisioningState}' \
  --output table
```

Confirm OKE ArgoCD can see the AKS apps:

```bash
kubectl --context oke-cluster -n argocd get applications.argoproj.io \
  aks-rocketchat-ops aks-rocketchat-helm aks-rocketchat-secrets \
  --output wide
```

Confirm MongoDB and PVC state on AKS:

```bash
kubectl --context aks-canepro -n rocketchat get mongodbcommunity mongodb -o yaml
kubectl --context aks-canepro -n rocketchat get pod,pvc,pv
kubectl --context aks-canepro -n rocketchat describe pvc data-volume-mongodb-0
```

Measure logical MongoDB size:

```bash
kubectl --context aks-canepro -n rocketchat exec mongodb-0 -c mongod -- \
  mongosh --quiet --eval 'db.getSiblingDB("rocketchat").stats(1024 * 1024)'
```

If `mongosh` is unavailable in the container, inspect available tools first:

```bash
kubectl --context aks-canepro -n rocketchat exec mongodb-0 -c mongod -- \
  sh -lc 'command -v mongosh || command -v mongo || ls /usr/bin | grep mongo'
```

## Backup gate

Do not continue unless a fresh backup exists outside the PVC being replaced.

Create a local-only backup directory outside Git-tracked paths:

```bash
mkdir -p ~/tmp/rocketchat-aks-mongo-backups
```

Create a fresh archive:

```bash
kubectl --context aks-canepro -n rocketchat exec mongodb-0 -c mongod -- \
  mongodump --archive=/tmp/rocketchat-mongo.archive --gzip

kubectl --context aks-canepro -n rocketchat cp \
  mongodb-0:/tmp/rocketchat-mongo.archive \
  ~/tmp/rocketchat-aks-mongo-backups/rocketchat-mongo-$(date -u +%Y%m%dT%H%M%SZ).archive.gz \
  -c mongod
```

Keep backups out of Git. Do not commit archives, secrets, connection strings, or Terraform state.

## GitOps change

Edit `ops/manifests/mongodb-community.yaml` only after the size check and backup are complete.

Example target:

```yaml
volumeClaimTemplates:
  - metadata:
      name: data-volume
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: managed-csi
      resources:
        requests:
          storage: 16Gi
```

Verify the storage class exists first:

```bash
kubectl --context aks-canepro get storageclass
```

Use the repo's normal PR/merge flow so ArgoCD on OKE is the deployment path. Avoid direct live edits except for the explicit maintenance actions below.

## Maintenance procedure

1. Start AKS and wait for ArgoCD to regain target-cluster connectivity.
2. Confirm the fresh backup and copy it off the MongoDB pod.
3. Scale Rocket.Chat workloads down so writes stop:

   ```bash
   kubectl --context aks-canepro -n rocketchat scale deploy rocketchat-rocketchat --replicas=0
   kubectl --context aks-canepro -n rocketchat scale deploy -l app.kubernetes.io/instance=rocketchat --replicas=0
   ```

4. Merge the GitOps manifest change.
5. Sync `aks-rocketchat-ops` from OKE ArgoCD, or let automated sync converge.
6. Delete the old MongoDB resource/PVC only after backup verification and after confirming the manifest has the new target.
7. Allow ArgoCD and the MongoDB operator to recreate MongoDB with the smaller PVC.
8. Copy the backup archive into the new MongoDB pod and restore:

   ```bash
   kubectl --context aks-canepro -n rocketchat cp \
     ~/tmp/rocketchat-aks-mongo-backups/<backup>.archive.gz \
     mongodb-0:/tmp/restore.archive.gz \
     -c mongod

   kubectl --context aks-canepro -n rocketchat exec mongodb-0 -c mongod -- \
     mongorestore --archive=/tmp/restore.archive.gz --gzip --drop
   ```

9. Scale Rocket.Chat back up and verify.
10. Stop AKS again.

## Verification

Required checks:

```bash
kubectl --context aks-canepro -n rocketchat get pod,pvc
kubectl --context aks-canepro -n rocketchat exec mongodb-0 -c mongod -- \
  mongosh --quiet --eval 'db.getSiblingDB("rocketchat").stats(1024 * 1024)'
kubectl --context aks-canepro -n rocketchat rollout status deploy/rocketchat-rocketchat
curl -fsS https://k8.canepro.me/api/info
az disk list -g MC_rg-canepro-aks_aks-canepro_uksouth \
  --query '[].{name:name,diskSizeGB:diskSizeGB,sku:sku.name,tags:tags}' \
  --output table
```

Expected outcome:

- New MongoDB PVC is the intended smaller size and storage class.
- Rocket.Chat starts and `/api/info` responds.
- Old 50Gi Premium disk is gone only after the replacement is verified.
- AKS is stopped after the maintenance window.

## Rollback

If restore or app verification fails:

1. Keep Rocket.Chat scaled down.
2. Revert the GitOps manifest to the previous PVC size/storage class.
3. Recreate MongoDB from the previous manifest.
4. Restore from the fresh archive again.
5. Do not delete the backup until Rocket.Chat has been verified.
