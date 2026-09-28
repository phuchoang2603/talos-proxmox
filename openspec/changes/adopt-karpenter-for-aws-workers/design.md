## Context

See proposal.md for motivation. The constraints that shape this design:

- Control planes run on Proxmox, not EC2. The controller has no instance metadata, no instance profile, and no EKS OIDC provider, so it needs its own AWS credential.
- Workers join from a Talos machine configuration that contains the cluster join token and CA material. With `amiFamily: Custom`, Karpenter passes `EC2NodeClass.spec.userData` to the instance unchanged, and the field is plain text on a cluster-scoped custom resource.
- The platform root already installs components that must exist before Argo CD (Gateway API CRDs, Cilium, Argo CD) and reads its inputs from the environment's Doppler config. The cluster root writes generated values to Doppler. The provisioning workflow destroys the platform root before the cluster root.
- Talos CCM sets `aws:///<zone>/<instance-id>` provider IDs on AWS workers. Karpenter matches NodeClaims to Nodes by provider ID.
- Dev has one control plane and prod has three.
- The Sidero guide for Omni (docs.siderolabs.com, "Autoscale Your Talos Cluster on AWS with Karpenter") confirms the Custom AMI family, discovery tags, and a single NodePool. It relies on Omni's AMI-embedded join and on the controller running on EC2, and neither applies here.

## Goals / Non-Goals

**Goals:**
- A single OpenTofu owner for every Karpenter object, so CRD ordering, secret `userData`, the controller credential, and teardown order stay in one dependency graph.
- A worker instance role with no permissions, and a controller credential that cannot reach the other environment.

**Non-Goals:**
- Spot interruption handling (SQS and EventBridge), keyless controller credentials (IAM Roles Anywhere or a self-hosted OIDC issuer), persistent storage on AWS workers, GPU or multiple NodePools, and private subnets or NAT. Each can be added later without changing this design.

## Decisions

### Karpenter is owned entirely by the platform root

The platform root installs three Helm releases in order, all in `kube-system`:

```
kubernetes_secret_v1.karpenter_aws ─┐
helm_release.karpenter_crd ─────────┼─▶ helm_release.karpenter ─▶ helm_release.karpenter_nodes
                                    │   (controller, skip CRDs)   (EC2NodeClass + NodePool)
```

- `apps/components/karpenter-crd`: the vendored upstream `karpenter-crd` chart, following the Gateway API precedent.
- `apps/components/karpenter`: a wrapper around the upstream `karpenter` chart with base values. The platform root sets `settings.clusterName`, `settings.clusterEndpoint`, and a checksum annotation of the credential Secret.
- `apps/components/karpenter-nodes`: a local chart that renders one `EC2NodeClass` and one `NodePool`. The platform root passes `userData` and the AMI ID with `set_sensitive` and `set`. Placeholder defaults in `values.yaml` keep `helm lint` working.

Both releases read `environments/<env>/values.yaml` through the existing `chart_values` mechanism, so per-environment limits and replica counts stay in Git.

Alternatives considered:
- *Argo CD owns the controller and NodePool; OpenTofu owns only the EC2NodeClass.* This splits Karpenter across two owners. The platform root would need the CRDs before Argo CD installs them, and destroying Argo CD could remove the controller while NodeClaims still exist, which leaves EC2 instances running.
- *Argo CD owns everything, with `userData` in Git or injected by a plugin.* This either commits Talos secrets or adds a secret-injection path that exists only for one field.

Consequence: Karpenter is not visible in the Argo CD UI, and changes to its charts deploy through the platform apply rather than an Argo CD sync.

### Worker bootstrap values reach the platform root through Doppler

The cluster root's AWS module keeps `data.talos_machine_configuration.worker` and outputs it. `doppler.tf` writes `AWS_WORKER_MACHINE_CONFIG` (yaml) and `AWS_WORKER_AMI_ID` alongside `KARPENTER_AWS_ACCESS_KEY_ID` and `KARPENTER_AWS_SECRET_ACCESS_KEY`, replacing `AUTOSCALER_AWS_*`. The platform root reads them from its existing `doppler_secrets` data source. Names that can be derived from the environment, such as the cluster name, the instance profile name `<env>-talos-burst-worker`, and the discovery tag value, are computed in both roots rather than passed.

Alternative considered: have the platform root read the cluster workspace's outputs through `tfe_outputs`. That adds a second hand-off mechanism and an HCP Terraform read dependency to the platform root.

The Talos worker patch changes in one place: `register-with-taints` adds `karpenter.sh/unregistered=true:NoExecute`, so nothing schedules before Karpenter has applied the NodePool's labels and taints. The `burst.talos.dev` label and taint stay in the Talos patch and are repeated in the NodePool template.

### The controller uses a static IAM key in a platform-owned Secret

The cluster root keeps the existing `aws_iam_user` and `aws_iam_access_key` pattern, renamed to `talos-proxmox-karpenter-<env>`. The platform root creates `kube-system/karpenter-aws` directly from Doppler. The controller reads it through `controller.env` entries with `secretKeyRef`, plus `AWS_REGION`. A pod annotation holding a checksum of the key ID restarts the controller when the key rotates, so rotation is a cluster apply followed by a platform apply.

Alternatives considered:
- *An ESO ExternalSecret.* ESO is installed later by Argo CD, so the controller would wait for a Secret owned by a different tool, and rotation would still need an Argo CD restart.
- *IAM Roles Anywhere, or a self-hosted OIDC issuer with `AssumeRoleWithWebIdentity`.* Neither needs a long-lived key, but both add a CA or kube-apiserver issuer changes. They are deferred to a later change.

### The controller IAM policy is scoped by environment tags

The policy lives at `terraform/aws/iam/karpenter-policy.json`. `ENV`, `CLUSTER`, and `ACCOUNT_ID` are substituted into it, following the existing autoscaler policy.

| Statement | Actions | Scope |
| --- | --- | --- |
| Read | `ec2:Describe*` (instances, types, offerings, images, subnets, SGs, launch templates, spot price history), `pricing:GetProducts` | `*` |
| Launch | `ec2:RunInstances`, `ec2:CreateFleet`, `ec2:CreateLaunchTemplate` | Request tag `kubernetes.io/cluster/<cluster>=owned`; subnets and SG tagged `karpenter.sh/discovery=<cluster>`; image restricted to the account's pinned Talos AMI ARNs |
| Tag at creation | `ec2:CreateTags` | Only with `ec2:CreateAction` in `RunInstances`, `CreateFleet`, `CreateLaunchTemplate`, and the cluster request tag |
| Manage owned | `ec2:TerminateInstances`, `ec2:DeleteLaunchTemplate`, `ec2:CreateTags` | Resource tag `kubernetes.io/cluster/<cluster>=owned` |
| Instance profile | `iam:PassRole` on `<env>-talos-burst-worker` with `iam:PassedToService=ec2.amazonaws.com`, and `iam:GetInstanceProfile` on that profile | Named |

`EC2NodeClass.spec.instanceProfile` names the pre-created profile, so Karpenter never needs IAM write permissions. The worker role trusts `ec2.amazonaws.com` and has no policies attached.

The AMI restriction takes the AMI ID from `aws_ami_id`, so a Talos upgrade updates the policy in the same cluster apply.

### Networking

`terraform/aws/network.tf` creates one public subnet per entry in `availability_zones` (default `["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]`), carved from the environment's VPC CIDR with `cidrsubnet(var.vpc_cidr, 8, index)`. Each subnet is associated with the existing public route table. Subnets and the worker security group get `karpenter.sh/discovery=<cluster>`. The EC2NodeClass selects them by that tag and sets `associatePublicIPAddress: true`, because KubeSpan and the discovery service need egress and inbound UDP 51820 without NAT.

### One NodePool

`aws-burst` (base values, with `environments/prod/values.yaml` overriding limits if needed):

| Field | Value |
| --- | --- |
| Requirements | `kubernetes.io/arch In [amd64]`, `karpenter.sh/capacity-type In [spot, on-demand]`, `karpenter.k8s.aws/instance-category In [c, m, r]`, `karpenter.k8s.aws/instance-generation Gt 5`, `karpenter.k8s.aws/instance-cpu In [2, 4, 8]` |
| Labels / taints | `burst.talos.dev/compute=aws`; `burst.talos.dev/stateless=true:NoSchedule` |
| Startup taints | `node.cloudprovider.kubernetes.io/uninitialized:NoSchedule`, `node.cilium.io/agent-not-ready:NoSchedule` |
| Limits | `cpu: 8`, `memory: 32Gi` |
| Disruption | `consolidationPolicy: WhenEmptyOrUnderutilized`, `consolidateAfter: 5m`, budget `nodes: "1"` |
| Lifetime | `expireAfter: 720h`, `terminationGracePeriod: 30m` |

The EC2NodeClass sets `amiFamily: Custom`, `amiSelectorTerms: [{id: <AMI>}]`, a 40 GiB `gp3` root volume (unencrypted, as before, to avoid KMS grants) on `/dev/xvda` deleted on termination, IMDSv2 required, and a `kubelet` block whose reservations and eviction thresholds match Talos defaults. Karpenter uses those values only to predict allocatable capacity; it does not apply them to Talos.

Karpenter treats both `spec.amiSelectorTerms` and `spec.userData` as drift inputs, which provides the replacement behavior the spec requires on Talos upgrades and config changes.

### Controller placement

The controller runs on control-plane nodes (control-plane `nodeSelector` and toleration). The chart's default zone topology spread is removed because Proxmox nodes have no zone label. Dev runs one replica; prod runs two with hostname anti-affinity and leader election. The pod keeps the chart's `system-cluster-critical` priority, which is why the releases live in `kube-system`.

### No interruption queue

`settings.interruptionQueue` is left empty. A reclaimed spot instance terminates about two minutes after the notice without an advance drain. Karpenter's NodeClaim garbage collection sees the missing instance, deletes the NodeClaim and Node, and provisions replacement capacity for the pods left pending. This fits a stateless-only pool. Adding SQS and EventBridge later only requires cluster-root resources and one setting.

### Teardown order

On destroy, OpenTofu reverses the dependency graph shown above. `helm_release.karpenter_nodes` is uninstalled first, with `wait = true` and a timeout above `terminationGracePeriod`. Deleting the NodePool cascades to its NodeClaims, which drain and terminate their instances. The EC2NodeClass finalizer blocks until no NodeClaims reference it and then deletes the launch templates Karpenter created. After that the controller release, the CRDs, and the Secret are removed. If instances somehow remain, the cluster root's VPC destroy fails because the subnets still have network interfaces in use, instead of silently orphaning them.

### CI permissions

`ci-policy.json` drops the Auto Scaling Group, launch template, and `RunInstances` statements. It keeps VPC, subnet, route, and security group management, and gains `ec2:DescribeAvailabilityZones`. `ci-iam-policy.json` renames the user and policy patterns to `talos-proxmox-karpenter-*` and adds create, delete, tag, and get permissions for the role and instance profile `*-talos-burst-worker`, along with `iam:AddRoleToInstanceProfile` and `iam:RemoveRoleFromInstanceProfile`. It grants no `iam:PassRole`, because CI never launches instances.

## Risks / Trade-offs

- [The Talos node does not register cleanly under Karpenter, for example the `karpenter.sh/unregistered` taint is not removed, or the provider ID never matches] → The dev spike in tasks.md proves one NodeClaim reaching `Ready` and `Initialized` before prod is touched.
- [Predicted allocatable differs from Talos's real allocatable, so Karpenter launches a node the pod doesn't fit on and loops] → The spike records the real allocatable per instance size, and the EC2NodeClass `kubelet` block is tuned until the prediction is at or below it.
- [The Karpenter release does not support Kubernetes 1.36] → Pin the newest release whose compatibility matrix includes 1.36. Stop the change if none does.
- [Spot reclaims without an interruption queue drop in-flight requests] → Accepted for stateless burst workloads. Workloads that cannot tolerate it select `karpenter.sh/capacity-type=on-demand`.
- [Destroy blocks on a PodDisruptionBudget that never allows eviction] → `terminationGracePeriod` forces termination after 30 minutes, and the Helm uninstall timeout is longer than that.
- [`userData` is readable by anyone who can get `ec2nodeclasses` or the Helm release Secret in `kube-system`] → Only cluster-admin-level operators can read these in this repository. The same material already exists in the HCP Terraform state and the Doppler config.
- [A Doppler value-size limit rejects the machine configuration] → The spike writes it once. If it is rejected, switch this one hand-off to `tfe_outputs`.
- [Karpenter changes are not visible in Argo CD] → Documented in the GitOps architecture ownership table.

## Migration Plan

This is a clean replacement applied from fresh state, not a coexistence period.

1. Spike on dev from an operator machine: apply the branch's cluster and platform roots locally against `talos-cluster-dev` and `talos-platform-dev`, then run the burst, consolidation, drift, and destroy checks.
2. Merge to `main`. CI applies dev and prod. The cluster apply removes the ASG and autoscaler user, and the platform apply installs Karpenter. Argo CD prunes the `cluster-autoscaler` application and the `burst-node-gc` resources.
3. Run the burst and return-to-zero checks on prod.

Rollback: revert the merge. The ASG, autoscaler, and cleanup CronJob return on the next apply. Workers Karpenter launched must be removed by the platform destroy order before the revert, or terminated from the AWS console.

## Open Questions

- Which exact Karpenter version to pin. This is decided at implementation time from the upstream compatibility matrix.
- Whether prod's limits should differ from dev's. They start equal, and changing them only touches a values overlay.
