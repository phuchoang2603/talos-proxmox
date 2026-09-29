## Why

An environment destroy spends most of its time, or all of its timeout, tearing down the platform root inside a cluster that is about to be deleted. On 2026-09-29 the dev and prod destroys both hung for 45 minutes in `helm_release.karpenter_nodes` with no AWS workers running: the `EC2NodeClass` termination finalizer looped on `AccessDenied` for `iam:ListInstanceProfiles`, because the Karpenter policy allows only the exact path `instance-profile/karpenter/<region>/<cluster>/` while Karpenter 1.14 lists `.../<cluster>/<nodeclass-uid>/`. Even with that fixed, a destroy with running workers waits up to the 30-minute `terminationGracePeriod` to drain pods whose nodes are being deleted anyway, and any destroy fails if the Kubernetes API is unreachable.

The platform root and the components Argo CD installs create nothing outside the cluster except Karpenter's EC2 instances and launch templates. If the cluster root removes those through AWS, a destroy does not need the platform teardown at all.

## What Changes

- Fix the Karpenter controller policy so `iam:ListInstanceProfiles` covers every path under `instance-profile/karpenter/<region>/<cluster>/`. The `EC2NodeClass` finalizer then completes whenever the node class is deleted.
- The cluster root's AWS module removes Karpenter-launched EC2 resources during destroy, before the subnets, security group, and worker instance profile: it first detaches the Karpenter policy so no new instance can launch, then terminates the environment's Karpenter-tagged instances, waits for them to terminate, and deletes their launch templates. It does not use the Kubernetes API or the Karpenter controller.
- **BREAKING** The provisioning workflow's destroy no longer destroys the platform root. It destroys the cluster root, then removes every resource from the platform root's state. Running `tofu destroy` on the platform root is no longer part of an environment destroy.
- The CI provisioning role gains read access to instances and launch templates and permission to terminate instances and delete launch templates tagged as Karpenter-managed by talos-proxmox. It still cannot launch instances.
- Document that the platform root and Argo CD-owned components must not create resources outside the cluster, because a destroy no longer runs their teardown.
- Update the destroy procedure in the operations, architecture, and CI documentation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `hybrid-aws-burst-workers`: the destroy cleanup of autoscaled instances and launch templates must happen through AWS without the cluster or the autoscaler, and must revoke the autoscaler's permissions first; removing the autoscaler's node configuration must complete without manual intervention; CI may terminate, but still not launch, autoscaled instances.
- `declarative-platform-bootstrap`: an environment destroy runs only the cluster root and then resets the platform root's state, does not need the Kubernetes API, and relies on the platform root and Argo CD components having no external side effects.

## Impact

- **OpenTofu:**
  - `terraform/aws/iam/karpenter-policy.json`: widen the `ListKarpenterInstanceProfiles` resource.
  - `terraform/aws/`: a destroy-time sweep resource ordered between the Karpenter policy attachment and the network and instance profile resources. The sweep uses the AWS CLI with the credentials of whoever runs the destroy.
  - `terraform/foundation/ci-policy.json`: instance and launch template Describe, Terminate, and Delete permissions scoped by tag. An operator applies the foundation root locally before the new destroy is used.
  - `terraform/platform/`: no resource changes. `helm_release.karpenter_nodes` keeps `wait = true` for applies that replace the NodePool.
- **CI:** `.github/workflows/provision.yml` removes the "Destroy platform" step and adds a platform state reset after the cluster destroy succeeds.
- **Docs:** `docs/operations/aws-burst-workers.md`, `docs/architecture/hybrid-aws-workers.md`, `docs/architecture/terraform-ci.md`, and `docs/architecture/gitops.md`.
- **Operations:** a destroy takes about as long as the cluster root destroy plus one to two minutes per round of instance termination, and succeeds when the cluster is broken or unreachable.
