# AWS burst workers

Dev and prod can add up to two stateless `m7i-flex.large` AWS workers each. Everything persistent stays on the fixed Proxmox nodes.

| Piece | Where |
| --- | --- |
| VPC, ASG (`dev-talos-burst` / `prod-talos-burst`), launch template, autoscaler IAM user and access key | `terraform/aws/`, called from `terraform/cluster/`; HCP Terraform workspace `talos-cluster-${env}` |
| Talos cloud controller manager (sets `aws:///<zone>/<instance-id>` provider IDs) and `burst-node-gc` CronJob | `apps/components/talos-ccm/`, Argo CD sync wave `0` |
| `burst-stateless-only` admission policy | `apps/components/burst-policy/`, Argo CD sync wave `-1` |
| Cluster Autoscaler and its `cluster-autoscaler-aws` ExternalSecret | `apps/components/cluster-autoscaler/`, Argo CD, runs on Proxmox control planes |

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

1. Remove the environment from `clusters` on `cluster-autoscaler` in `apps/argocd/platform/values.yaml` and push to `main`. That environment's Argo CD prunes the autoscaler; scaling its Deployment by hand is reverted by self-heal.
2. Drain the AWS nodes as above, then scale the group to zero:

   ```bash
   aws autoscaling set-desired-capacity --region us-east-1 \
     --auto-scaling-group-name dev-talos-burst --desired-capacity 0
   ```

3. Wait for `burst-node-gc`, or delete the Node objects yourself: `kubectl delete node -l burst.talos.dev/compute=aws`.

Removing the AWS module is a separately reviewed change: it also deletes the autoscaler user and the key the cluster uses.

## Rotate the autoscaler access key

Each environment's key belongs to `talos-proxmox-autoscaler-${env}` and can scale only `${env}-talos-burst`. OpenTofu owns it as `module.aws.aws_iam_access_key.autoscaler` and writes it to Doppler; ESO copies it into `cluster-autoscaler/cluster-autoscaler-aws` every 5 minutes. CI uses short-lived GitHub OIDC sessions and has no static AWS key.

1. Replace the key with a local apply of the cluster root (see [Local OpenTofu](./doppler-setup.md#local-opentofu)):

   ```bash
   tofu apply -var-file=env/dev/main.tfvars -replace=module.aws.aws_iam_access_key.autoscaler
   ```

   `create_before_destroy` creates the new key and updates `AUTOSCALER_AWS_*` in Doppler before deleting the old key.

2. Wait up to 5 minutes for the ExternalSecret to refresh (`kubectl -n cluster-autoscaler get externalsecret cluster-autoscaler-aws`).
3. In the environment's Argo CD UI, open the `cluster-autoscaler` Application and use **Restart** on the Deployment.
4. Confirm the logs show `Registering ASG dev-talos-burst` without `AccessDenied` or `InvalidClientTokenId`.

## Inspect infrastructure state

AWS resources share each environment's cluster state; there is no separate AWS root. Follow [Local OpenTofu](./doppler-setup.md#local-opentofu) in `terraform/cluster/` with `TF_WORKSPACE=talos-cluster-${env}` and `-var-file=env/${env}/main.tfvars`, then run `tofu state list module.aws`.

## Known limits

- Cross-site pod traffic carries packets up to 1370 bytes; Cilium's MTU is pinned to 1500 so AWS pods match. IP-fragmented pod traffic is dropped between any two nodes, on-premises pairs included.
- Traffic from on-premises to AWS is limited by the site's upload bandwidth.
- Rebooting one control plane leaves AWS workers Ready because KubePrism switches to the remaining control planes. The LAN VIP moves to another control plane, but `/readyz` can report the etcd check as failed for a few seconds while the rebooted member rejoins.
