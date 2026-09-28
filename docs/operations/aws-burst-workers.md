# AWS worker operations

[Documentation home](../../README.md) · [Hybrid AWS architecture](../architecture/hybrid-aws-workers.md)

Use this guide to place a stateless workload on AWS, observe scaling, disable bursting, or rotate the autoscaler key. First [select the cluster](cluster-access.md#select-an-environment). AWS inspection/maintenance commands also require the AWS CLI and an operator AWS session; the CLI is not included in `devenv.nix`.

## Schedule a workload

Add this to the workload's Pod spec (`spec.template.spec` for a Deployment):

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

The toleration permits AWS placement; the affinity requires it, so the Pod waits for burst capacity rather than landing on Proxmox. Set CPU and memory requests on its containers. A single worker advertises 1950m CPU, 7274Mi memory, and 32Gi ephemeral storage before system workload overhead is considered by scheduling.

Use no PVCs, generic ephemeral volumes, or persistent claim templates. `emptyDir` is allowed but disappears with the worker. The admission policy rejects persistent workloads opting into AWS. Store the workload definition in its usual Git-managed location so Argo CD can reconcile it.

## Observe scaling

```bash
kubectl get nodes -l burst.talos.dev/compute=aws -o wide
kubectl -n cluster-autoscaler logs deploy/cluster-autoscaler-aws-cluster-autoscaler \
  --tail=200 | rg 'scale-up plan|Scale-down|Registering ASG|AccessDenied|InvalidClientTokenId'
aws autoscaling describe-auto-scaling-groups --region us-east-1 \
  --auto-scaling-group-names "${CLUSTER_ENV}-talos-burst" \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]'
```

A zero desired count is normal when idle. Each group is bounded at two workers. Once workloads finish, scale-down depends on the configured delays and eviction constraints; stale NotReady burst Node objects are later removed by the cleanup CronJob.

If a Pod stays Pending, inspect its events and check:

| Check | Why it matters |
| --- | --- |
| Requests fit the node template | An oversized Pod cannot fit even if a new node starts |
| Taint toleration and node affinity | Scheduling intent must match the ASG template |
| ASG is below maximum and can launch the pinned AMI | Capacity bounds or EC2 launch failures can prevent scale-up |
| Autoscaler Secret is Ready and logs show ASG registration | Stale/invalid credentials prevent AWS API calls |
| New node has mesh connectivity, cloud identity, and Cilium | A launched EC2 instance is not yet a Ready Kubernetes node |

See [the join sequence](../architecture/hybrid-aws-workers.md#scale-from-zero-then-return-to-zero) for the responsibilities of each component.

## Return to zero or disable bursting

For normal scale-down, remove or scale down the burst workloads through their Git owner and let the autoscaler remove unneeded nodes. Leaving AWS-only workloads Pending can trigger new capacity.

To disable automatic bursting for an environment:

1. Remove that environment from `clusters` for `cluster-autoscaler` in [`apps/argocd/platform/values.yaml`](../../apps/argocd/platform/values.yaml), merge, and wait for Argo CD to prune its Application/resources.
2. Remove or scale down burst workloads, then drain remaining AWS nodes. Draining removes their disposable local data:

   ```bash
   kubectl drain -l burst.talos.dev/compute=aws \
     --ignore-daemonsets --delete-emptydir-data
   ```

3. Set the group to zero with an operator AWS session:

   ```bash
   aws autoscaling set-desired-capacity --region us-east-1 \
     --auto-scaling-group-name "${CLUSTER_ENV}-talos-burst" --desired-capacity 0
   ```

4. Wait for the stale-node cleanup CronJob. If necessary, inspect and remove the terminated workers' Node objects.

OpenTofu ignores desired capacity, so a routine apply will not turn it back up. Restore the environment's autoscaler membership in Git to re-enable automatic scaling. Deleting the AWS module is a larger infrastructure removal: it also removes the IAM user and key.

## Rotate the autoscaler key

Start at the repository root and follow [local OpenTofu setup](../../CONTRIBUTING.md#run-opentofu-locally). Select the same environment as your kubeconfig:

```bash
export TF_VAR_env="$CLUSTER_ENV"
export TF_WORKSPACE="talos-cluster-${TF_VAR_env}"
tofu -chdir=terraform/cluster init
tofu -chdir=terraform/cluster apply \
  -var-file="env/${TF_VAR_env}/main.tfvars" \
  -replace=module.aws.aws_iam_access_key.autoscaler
```

Review the replacement before approving it. OpenTofu creates the replacement key and updates Doppler as part of the apply. ESO refreshes `cluster-autoscaler/cluster-autoscaler-aws` every five minutes. There can be an authentication gap until the Secret and process use the new key.

1. Wait for the ExternalSecret to refresh successfully:

   ```bash
   kubectl -n cluster-autoscaler get externalsecret cluster-autoscaler-aws
   ```

2. In the environment's Argo CD UI, use **Restart** on the autoscaler Deployment.
3. Check logs for successful registration of the environment's ASG without `AccessDenied` or `InvalidClientTokenId`.

CI's OIDC session is independent of this key. Do not create a replacement key manually in AWS or copy it into Kubernetes.

## Inspect AWS resources in state

With the environment's cluster workspace initialized:

```bash
tofu -chdir=terraform/cluster state list module.aws
```

AWS resources share cluster state with Proxmox and Talos. They do not have a separate root or workspace.
