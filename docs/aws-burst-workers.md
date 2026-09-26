# AWS burst workers

Dev and prod can add up to two stateless `m7i-flex.large` AWS workers each. Everything persistent stays on the fixed Proxmox nodes.

| Piece | Where |
| --- | --- |
| VPC, ASG (`dev-talos-burst` / `prod-talos-burst`), launch template, autoscaler IAM user | `terraform/aws/`, called from `terraform/cluster/`; state key `talos-${env}.tfstate` in MinIO |
| Talos cloud controller manager (sets `aws:///<zone>/<instance-id>` provider IDs) and `burst-node-gc` CronJob | `apps/components/talos-ccm/`, installed by `apps/bootstrap/bootstrap.sh` |
| `burst-stateless-only` admission policy | `apps/components/burst-policy/`, Argo CD sync wave `-1` |
| Cluster Autoscaler | `apps/components/cluster-autoscaler/`, Argo CD, runs on Proxmox control planes |

AWS workers register with the `burst.talos.dev/stateless=true:NoSchedule` taint and the `burst.talos.dev/compute=aws` label. They reach the API through KubeSpan and local KubePrism; the private LAN VIP is never exposed.

## Opt a workload in

A pod runs on AWS only if it tolerates the burst taint. Add positive affinity so it waits for AWS capacity instead of landing on Proxmox:

```yaml
tolerations:
  - key: burst.talos.dev/stateless
    operator: Equal
    value: "true"
    effect: NoSchedule
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: burst.talos.dev/compute
              operator: In
              values: [aws]
```

Set CPU and memory requests. The autoscaler's zero-size template advertises 1950m CPU, 7274Mi memory and 32Gi ephemeral storage per worker, so larger pods never trigger a scale-up.

Use only `emptyDir` for scratch; it is lost when the worker terminates. The admission policy rejects Pods and StatefulSets that tolerate the burst taint (including wildcard `operator: Exists` tolerations) while using PVC, generic ephemeral, or `volumeClaimTemplates` volumes, and PVC-bearing Pods bound directly to an `ip-*` AWS node.

## Observe

```bash
export KUBECONFIG=~/.kube/talos-dev.yaml   # or talos-prod.yaml
kubectl get nodes -l burst.talos.dev/compute=aws -o wide
kubectl -n cluster-autoscaler logs deploy/cluster-autoscaler-aws-cluster-autoscaler | grep -E 'scale-up plan|Scale-down'
aws autoscaling describe-auto-scaling-groups --region us-east-1 \
  --auto-scaling-group-names dev-talos-burst \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]'
```

A worker is Ready about three minutes after scale-up. After its burst pods are gone, the autoscaler removes it within about ten minutes. `burst-node-gc` then deletes the leftover NotReady Node object after 15 minutes.

The autoscaler owns `DesiredCapacity`; OpenTofu ignores it, so a `main` apply does not reset a running burst.

## Drain and roll back

To remove burst capacity now while keeping the feature:

```bash
kubectl drain -l burst.talos.dev/compute=aws --ignore-daemonsets --delete-emptydir-data
```

Opted-in pods go back to Pending. The autoscaler scales the drained nodes to zero, but starts a new worker while those pods stay Pending, so scale the opted-in workloads down too.

To turn bursting off:

1. Set `enabled: false` on `cluster-autoscaler` in `apps/argocd/platform/values.yaml` and push to `main`. Argo CD prunes the autoscaler; scaling its Deployment by hand is reverted by self-heal.
2. Drain the AWS nodes as above, then scale the group to zero:

   ```bash
   aws autoscaling set-desired-capacity --region us-east-1 \
     --auto-scaling-group-name dev-talos-burst --desired-capacity 0
   ```

3. Wait for `burst-node-gc`, or delete the Node objects yourself: `kubectl delete node -l burst.talos.dev/compute=aws`.

Removing the AWS module is a separately reviewed change: its autoscaler IAM user has `prevent_destroy`, and its access key lives outside Terraform.

## Rotate the autoscaler access key

Each environment's key belongs to `talos-proxmox-autoscaler-${env}` and can scale only `${env}-talos-burst`. CI uses short-lived GitHub OIDC sessions and has no static AWS key.

1. Create a second key (IAM allows two per user):

   ```bash
   aws iam create-access-key --user-name talos-proxmox-autoscaler-dev
   ```

2. Store it in the matching Doppler config (`dev` or `prod`) as `AUTOSCALER_AWS_ACCESS_KEY_ID` and `AUTOSCALER_AWS_SECRET_ACCESS_KEY`.
3. Update the cluster Secret and restart the autoscaler (a `main` push re-runs bootstrap and updates the Secret, but does not restart the pod):

   ```bash
   doppler run --config dev --only-secrets AUTOSCALER_AWS_ACCESS_KEY_ID,AUTOSCALER_AWS_SECRET_ACCESS_KEY -- \
     sh -c 'kubectl -n cluster-autoscaler create secret generic cluster-autoscaler-aws \
       --from-literal=AWS_ACCESS_KEY_ID="$AUTOSCALER_AWS_ACCESS_KEY_ID" \
       --from-literal=AWS_SECRET_ACCESS_KEY="$AUTOSCALER_AWS_SECRET_ACCESS_KEY" \
       --dry-run=client -o yaml | kubectl apply -f -'
   kubectl -n cluster-autoscaler rollout restart deploy/cluster-autoscaler-aws-cluster-autoscaler
   ```

4. Confirm the logs show `Registering ASG dev-talos-burst` without `AccessDenied` or `InvalidClientTokenId`.
5. Deactivate and then delete the old key:

   ```bash
   aws iam update-access-key --user-name talos-proxmox-autoscaler-dev --access-key-id OLD_KEY_ID --status Inactive
   aws iam delete-access-key --user-name talos-proxmox-autoscaler-dev --access-key-id OLD_KEY_ID
   ```

## Inspect infrastructure state

AWS resources share each environment's cluster state; there is no separate AWS root. Follow [Local OpenTofu](./doppler-setup.md#local-opentofu) in `terraform/cluster/` with `-backend-config="key=talos-${env}.tfstate"` and `-var-file=env/${env}/main.tfvars`, then run `tofu state list module.aws`. Argocd has no `module.aws` instance.

## Known limits

- Cross-site pod traffic carries packets up to 1370 bytes; Cilium's MTU is pinned to 1500 so AWS pods match. IP-fragmented pod traffic is dropped between any two nodes, on-premises pairs included.
- Traffic from on-premises to AWS is limited by the site's upload bandwidth.
- Rebooting one control plane leaves AWS workers Ready because KubePrism switches to the remaining control planes. The LAN VIP moves to another control plane, but `/readyz` can report the etcd check as failed for a few seconds while the rebooted member rejoins.
