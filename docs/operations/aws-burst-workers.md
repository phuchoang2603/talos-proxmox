# AWS worker operations

[Documentation home](../../README.md) · [Hybrid AWS architecture](../architecture/hybrid-aws-workers.md)

Use this guide to place a stateless workload on AWS, observe scaling, pause bursting, or rotate the Karpenter key. First [select the cluster](cluster-access.md#select-an-environment). AWS inspection commands also require the AWS CLI and an operator AWS session; the CLI is not included in `devenv.nix`.

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

The toleration permits AWS placement; the affinity requires it, so the Pod waits for burst capacity rather than landing on Proxmox. Set CPU and memory requests on its containers. Karpenter chooses an instance that fits them, up to 8 vCPUs, and can use spot capacity. To require on-demand capacity for a workload that cannot tolerate a sudden spot reclaim, add a node selector:

```yaml
nodeSelector:
  karpenter.sh/capacity-type: on-demand
```

Use no PVCs, generic ephemeral volumes, or persistent claim templates. `emptyDir` is allowed but disappears with the worker. The admission policy rejects persistent workloads opting into AWS. Store the workload definition in its usual Git-managed location so Argo CD can reconcile it.

## Observe scaling

```bash
kubectl get nodepool,ec2nodeclass
kubectl get nodeclaims -o wide
kubectl get nodes -l burst.talos.dev/compute=aws -o wide
kubectl -n kube-system logs deploy/karpenter --tail=200
```

No NodeClaims and no AWS nodes is normal when idle. After workloads finish, Karpenter drains and removes unneeded workers once the five-minute consolidation delay has passed; eviction constraints such as PodDisruptionBudgets can delay it. The Node object is removed along with the instance.

If a Pod stays Pending, inspect its events and the NodeClaim, and check:

| Check | Why it matters |
| --- | --- |
| Requests fit an allowed instance | Pods larger than 8 vCPUs, or than the NodePool's remaining limit, cannot be scheduled |
| Taint toleration and node affinity | Scheduling intent must match the NodePool's taint and label |
| `kubectl describe nodepool aws-burst` shows limits not reached | Total CPU and memory are capped |
| Karpenter logs show no `AccessDenied` or launch errors | Stale credentials, insufficient capacity, and a wrong AMI all fail at launch |
| New node has mesh connectivity, cloud identity, and Cilium | A launched EC2 instance is not yet a Ready Kubernetes node |

If Karpenter launches a node that a pod does not fit on, compare `kubectl get nodeclaim -o yaml` allocatable with the Node's allocatable and adjust the `kubelet` values in [`apps/components/karpenter-nodes/values.yaml`](../../apps/components/karpenter-nodes/values.yaml).

See [the join sequence](../architecture/hybrid-aws-workers.md#scale-from-zero-then-return-to-zero) for the responsibilities of each component.

## Return to zero or pause bursting

For normal scale-down, remove or scale down the burst workloads through their Git owner and let Karpenter remove unneeded nodes. Leaving AWS-only workloads Pending can trigger new capacity.

To stop new AWS capacity for an environment, set the NodePool limits to zero in `apps/components/karpenter-nodes/environments/<env>/values.yaml`:

```yaml
nodePool:
  limits:
    cpu: "0"
    memory: 0Gi
```

Merge it and let the platform apply run. Existing workers keep running until their workloads finish and consolidation removes them. To remove them immediately, delete the workloads or drain the nodes and let Karpenter terminate them:

```bash
kubectl drain -l burst.talos.dev/compute=aws \
  --ignore-daemonsets --delete-emptydir-data
```

Draining removes their disposable local data. Restore the limits to resume bursting. Deleting the AWS module is a larger infrastructure removal: it also removes the IAM user, key, and worker role.

## Rotate the Karpenter key

Start at the repository root and follow [local OpenTofu setup](../../CONTRIBUTING.md#run-opentofu-locally). Select the same environment as your kubeconfig:

```bash
export TF_VAR_env="$CLUSTER_ENV"
export TF_WORKSPACE="talos-cluster-${TF_VAR_env}"
tofu -chdir=terraform/cluster init
tofu -chdir=terraform/cluster apply \
  -var-file="env/${TF_VAR_env}/main.tfvars" \
  -replace=module.aws.aws_iam_access_key.karpenter
```

Review the replacement before approving it. OpenTofu creates the replacement key and updates Doppler as part of the apply. Then apply the platform root for the same environment:

```bash
export TF_WORKSPACE="talos-platform-${TF_VAR_env}"
tofu -chdir=terraform/platform init
tofu -chdir=terraform/platform apply
```

The platform apply updates the `kube-system/karpenter-aws` Secret and restarts the controller, so there is no Argo CD restart. Check the controller logs for launches without `AccessDenied` or `InvalidClientTokenId`.

CI's OIDC session is independent of this key. Do not create a replacement key manually in AWS or copy it into Kubernetes.

## Destroy an environment with running workers

Use the **Manual Provision** destroy workflow. The platform root is destroyed first: it removes the NodePool, waits for Karpenter to terminate its instances (up to 30 minutes for workloads that ignore eviction), and then removes the controller and CRDs. If the wait fails, list the environment's remaining instances before retrying:

```bash
aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_ENV}-talos,Values=owned" \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId'
```

## Inspect AWS resources in state

With the environment's cluster workspace initialized:

```bash
tofu -chdir=terraform/cluster state list module.aws
```

AWS resources share cluster state with Proxmox and Talos. They do not have a separate root or workspace. Karpenter-launched instances and launch templates are not in state; Karpenter owns them.
