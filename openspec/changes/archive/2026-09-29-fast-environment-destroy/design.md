## Context

See proposal.md for motivation. The current state and constraints that shape the approach:

- `provision.yml` destroys in two steps: `tofu destroy` on the platform root (`talos-platform-<env>`), then on the cluster root (`talos-cluster-<env>`). Both use HCP Terraform workspaces with local execution, reached from the runner through Tailscale.
- The platform root holds only in-cluster objects: Helm releases for Gateway API, Cilium, Argo CD and its bootstrap chart, and the three Karpenter releases, plus two Doppler-derived Secrets and a namespace. It reads the kubeconfig from Doppler, which the cluster root writes and deletes.
- Argo CD Applications carry `resources-finalizer.argocd.argoproj.io/foreground`, but `argocd_bootstrap` is `wait = false` and Argo CD is uninstalled right after it, so Argo-owned components are not cascaded today either. They disappear with the VMs.
- Karpenter creates two kinds of AWS objects outside OpenTofu state: EC2 instances and launch templates. Both carry `kubernetes.io/cluster/<cluster>=owned`, `karpenter.sh/nodepool`, and the `EC2NodeClass` tag `managed-by=talos-proxmox`; the controller policy requires the first two at creation. `EC2NodeClass.spec.instanceProfile` names the pre-created profile, so Karpenter creates no instance profiles.
- The cluster root's AWS module owns the VPC, subnets, security group, worker role and instance profile, and the Karpenter IAM user, policy, attachment, and key. Its destroy fails with `DependencyViolation` if an instance's network interface still uses a subnet or the security group.
- The CI role (`terraform/foundation/ci-policy.json`) has no instance or launch template permissions. The foundation root is applied only by an operator.
- On 2026-09-29 both destroys failed at the `karpenter-nodes` uninstall. Argo CD was already uninstalled; the Karpenter controller, CRDs, Cilium, and Gateway API releases remain, and `EC2NodeClass/aws-burst` is stuck deleting.

## Goals / Non-Goals

**Goals:**
- The destroy's correctness depends only on AWS and OpenTofu state, never on the Kubernetes API, Argo CD, or the Karpenter controller.
- A local `tofu destroy` of the cluster root is as safe as the CI destroy.

**Non-Goals:**
- Moving Karpenter to Argo CD. With the cleanup owned by AWS it becomes possible, but the `userData` delivery problem from the Karpenter design is unchanged.
- A platform-only destroy. `destroy` in the workflow always means the whole environment.
- Changing how the platform root applies, including `wait = true` on `karpenter_nodes`, which still protects applies that replace the NodePool.

## Decisions

### Fix the Karpenter `ListInstanceProfiles` resource

`ListKarpenterInstanceProfiles` becomes `arn:aws:iam::ACCOUNT_ID:instance-profile/karpenter/REGION/CLUSTER/*`. IAM evaluates `ListInstanceProfiles` against the requested path prefix, and Karpenter 1.14 appends the node class UID. The trailing `*` also matches the bare prefix, and it stays scoped to the environment's cluster.

Alternative considered: `"Resource": "*"`, as in Karpenter's reference policy. It lets one environment's key enumerate the other's instance profiles for no benefit.

After listing, the finalizer also calls `iam:GetInstanceProfile` on the name of the profile it would have created, `<cluster>_<hash>`, even though `spec.instanceProfile` means it never created one. IAM answers `AccessDenied` before `NoSuchEntity`, so `ReadWorkerInstanceProfile` also allows `GetInstanceProfile` on `instance-profile/*CLUSTER_*`. The call is read-only and matches only the environment's own names. Karpenter still gets no IAM write permission, because no managed profile ever exists to delete.

This fix is independent of the rest of the change. It is needed for any apply that replaces or deletes the `EC2NodeClass`, and it unblocks the stuck node classes.

### The AWS module sweeps Karpenter resources during destroy

A `terraform_data.karpenter_sweep` resource in `terraform/aws/` does nothing on create and runs a destroy-time `local-exec` provisioner. Its dependencies place it in the destroy graph:

```
aws_iam_user_policy_attachment.karpenter ──depends_on──▶ terraform_data.karpenter_sweep
                                                                │ depends_on
                                                                ▼
           aws_subnet.worker, aws_security_group.worker, aws_internet_gateway.worker,
           aws_iam_instance_profile.worker

destroy order:  detach Karpenter policy ▶ sweep ▶ subnets, security group, internet gateway,
                instance profile, VPC
```

The internet gateway is included because AWS refuses to detach it while instances in the VPC hold public IPs.

- Detaching the policy revokes every Karpenter permission, so the controller cannot launch replacements whether or not it is still running. The Proxmox VMs are destroyed in parallel, which eventually stops the controller too, but correctness does not rely on it.
- The provisioner reads the region and cluster name from `self.input`, because destroy provisioners can reference only `self`. Values go in `input`, never `triggers_replace`: changing `input` updates in place, while a replacement would run the sweep during an apply and terminate running workers.
- The sweep loop:
  1. List instances in states `pending`, `running`, `stopping`, and `stopped` with `tag:kubernetes.io/cluster/<cluster>=owned` and `tag-key=karpenter.sh/nodepool`.
  2. If any exist, terminate them and run `aws ec2 wait instance-terminated`. A terminated instance has released its network interface, so the subnet and security group can be deleted.
  3. Repeat until a listing is empty and at least 60 seconds have passed since the sweep started, which covers IAM propagation after the detach. Fail after 15 minutes.
  4. Delete launch templates with `tag:kubernetes.io/cluster/<cluster>=owned` and `tag-key=karpenter.sh/nodepool`.
- The command is an inline heredoc in the resource rather than a file under the repository, in keeping with the rule against repository scripts. It uses the AWS CLI with the same credential chain as the AWS provider: the OIDC role in CI, or the operator's session locally. GitHub's `ubuntu-latest` image includes the CLI.
- A provisioner failure fails the destroy before the network resources are touched, and a retry reruns the sweep.

Alternatives considered:
- *A workflow step before the cluster destroy.* Simpler, but a local destroy would skip it, and it could not order itself between the policy detach and the network removal.
- *Rely on the platform root teardown, with the IAM fix.* Correct, but it keeps the drain wait and the dependency on a reachable API.
- *Only check for leftover instances and fail.* Safe, but it keeps a manual step for exactly the case the spec describes.

### Destroy skips the platform root and wipes its state afterwards

`provision.yml` drops the "Destroy platform" step. After the "Cluster" step succeeds on a destroy, a "Reset platform state" step runs in `terraform/platform` with `TF_WORKSPACE=talos-platform-<env>`:

```
tofu init -input=false
tofu state list > .resources
[ -s .resources ] && xargs tofu state rm < .resources
```

Steps stop at the first failure, so the reset runs only after a successful cluster destroy. Wiping first would be unsafe: if the cluster survived, the next apply would try to install every release again and fail with "cannot re-use a name that is still in use". `state rm` uses only the backend. It does not read the Doppler kubeconfig, which the cluster destroy has already removed, and it does not contact the cluster.

The next apply then runs against empty platform state, which is the path already used for every fresh environment.

Alternatives considered:
- *Leave the state stale.* The Helm and Kubernetes providers drop resources they cannot find during refresh, so the next apply would probably converge. It relies on per-provider "not found" handling against a new cluster, a path that is otherwise never exercised, and the workspace would misreport what exists.
- *Delete and recreate the HCP workspace.* It needs the HCP API and recreating the workspace's tags and settings for no benefit over an empty state.

### The CI role may terminate, but not launch, Karpenter resources

`ci-policy.json` gains:

| Statement | Actions | Scope |
| --- | --- | --- |
| Read | `ec2:DescribeInstances`, `ec2:DescribeLaunchTemplates` | `*`, added to `ReadInfrastructure` |
| Remove Karpenter resources | `ec2:TerminateInstances`, `ec2:DeleteLaunchTemplate` | `instance/*` and `launch-template/*` with `aws:ResourceTag/managed-by=talos-proxmox` and `aws:ResourceTag/karpenter.sh/nodepool` present |

A condition key cannot contain a wildcard, so the policy cannot express `kubernetes.io/cluster/*-talos=owned`. `managed-by` plus `karpenter.sh/nodepool` restricts it to Karpenter-launched resources of this repository in either environment; the sweep's own filter restricts it to one cluster. CI still has no `RunInstances`, `CreateFleet`, or `CreateLaunchTemplate`.

### The platform root stays cluster-internal

`docs/architecture/gitops.md` states the rule from the spec: the platform root and Argo CD components must not create resources outside the cluster that need removal on destroy. Their removal belongs in the cluster or foundation root. The components reviewed for this change comply: the Cloudflare tunnel exists independently and the cluster only holds its token, and Longhorn backups are meant to outlive the cluster.

## Risks / Trade-offs

- [IAM propagation lets Karpenter launch one more instance after the detach] → The sweep keeps listing for at least 60 seconds after it starts and terminates anything that appears.
- [Someone replaces `terraform_data.karpenter_sweep` during an apply, for example with `-replace`, and the destroy provisioner terminates running workers] → Only `input` holds values, and the resource carries a comment explaining that replacing it terminates workers. Workers are stateless, and Karpenter relaunches capacity once the resource is recreated.
- [`tofu state rm` evaluates provider or data source configuration and fails without a cluster] → Verified on dev during implementation. If it does, the reset step uses `tofu state push` with an empty state of the next serial instead.
- [A future component creates external resources, such as DNS records or tailnet devices, and a destroy leaks them] → The documented rule, and the spec scenario that assigns their removal to the cluster or foundation root.
- [The operator's AWS session lacks termination permissions during a local destroy] → The provisioner fails before any network resource is destroyed, and the destroy can be retried with a sufficient session.
- [The sweep adds one to two minutes per round of terminations to a destroy with workers] → Much less than the current drain wait of up to 30 minutes.

## Migration Plan

1. An operator applies the foundation root locally so the CI role has the new permissions before the new destroy runs.
2. Merge to `main`. The push-triggered apply runs the cluster root, which updates the Karpenter policy and adds the sweep resource without touching running infrastructure, then the platform root, which reinstalls Argo CD and `karpenter-nodes` on the half-destroyed dev and prod clusters. The fixed policy lets the stuck `EC2NodeClass` finalizers complete within about a minute. If the platform apply reaches `karpenter-nodes` before the old node class is gone and fails, rerun it.
3. Validate on dev with the Manual Provision destroy, once with no AWS workers and once with a burst workload running. Confirm no instances or launch templates remain for `dev-talos` and the platform workspace is empty. Then apply dev again and confirm it provisions from empty platform state.

Rollback: revert the merge and apply the foundation root from the reverted commit. The platform workspace is only empty right after a destroy, and the reverted workflow provisions it from empty state as before.
