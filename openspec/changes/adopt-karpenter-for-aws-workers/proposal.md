## Why

AWS burst capacity runs through Cluster Autoscaler on a fixed Auto Scaling Group: one instance type, one subnet, at most two on-demand workers, hand-measured capacity tags, and a CronJob that deletes stale Node objects the autoscaler leaves behind. Karpenter provisions EC2 instances directly from pending pods, chooses among many instance types and spot or on-demand capacity, consolidates idle nodes, deletes Node objects on termination, and replaces workers when their AMI or Talos configuration changes. The environments can be rebuilt from fresh state, so this is a clean replacement rather than a staged migration.

## What Changes

- **BREAKING** Remove Cluster Autoscaler: the `cluster-autoscaler` component and its Argo CD entry, the Auto Scaling Group, the launch template, the `k8s.io/cluster-autoscaler/*` tags, the autoscaler IAM user and policy, and the `AUTOSCALER_AWS_*` Doppler secrets.
- **BREAKING** Remove the `burst-node-gc` CronJob from `talos-ccm`. Karpenter's termination finalizer deletes Node objects. Talos CCM stays to set AWS provider IDs.
- Add Karpenter, owned entirely by the platform root: the CRD chart, the controller, one `EC2NodeClass`, and one `NodePool`. The `EC2NodeClass` uses `amiFamily: Custom`, the pinned Talos AMI, and the Talos worker machine configuration as `userData`, so no worker bootstrap material is committed to Git.
- One `NodePool`, `aws-burst`: amd64, spot and on-demand, a list of free-tier-eligible instance types, CPU and memory limits instead of a node count, consolidation when empty or underutilized, and periodic expiry. Workers keep the `burst.talos.dev/compute=aws` label and the `burst.talos.dev/stateless=true:NoSchedule` taint.
- No interruption queue. Spot reclaims are not drained in advance; stateless burst pods are rescheduled, and Karpenter cleans up the lost NodeClaim and Node.
- The cluster root's AWS module creates public subnets in several availability zones, tags subnets and the worker security group for Karpenter discovery, creates a worker IAM role and instance profile with no permissions, and creates a Karpenter IAM user whose policy is scoped to its environment's cluster tags, subnets, security group, AMI, and worker role.
- The cluster root writes the Karpenter access key, the worker machine configuration, and the worker AMI ID to Doppler. The platform root reads them and creates the controller's AWS credential Secret directly, which becomes the second platform-owned Doppler-derived Secret. Rotating the key requires only OpenTofu applies; the controller restarts from a checksum annotation.
- The platform root removes the `NodePool` and waits for Karpenter to terminate its instances before removing the controller, so an environment destroy leaves no running EC2 instances or launch templates outside OpenTofu state.
- The CI provisioning role loses Auto Scaling Group, launch template, and `RunInstances` permissions and gains management of the Karpenter user and policy and the worker role and instance profile.
- Rewrite the AWS worker architecture, operations, and secrets documentation for Karpenter.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `hybrid-aws-burst-workers`: AWS workers are provisioned by Karpenter within resource limits instead of by an Auto Scaling Group within a node count; spot capacity and interruption behavior, Node cleanup, and drift replacement become required behavior; teardown must remove Karpenter-launched instances; the scaling credential's scope is described in terms of Karpenter.
- `doppler-secret-delivery`: generated credentials include the Karpenter access key and the worker bootstrap values; the platform root owns the Karpenter credential Secret as a second exception to ESO delivery; key rotation no longer requires an Argo CD restart.

## Impact

- **OpenTofu:**
  - `terraform/aws/`: remove the Auto Scaling Group, the launch template, and the autoscaler IAM user; add subnets per availability zone, discovery tags, the worker role and instance profile, and the Karpenter IAM user, policy, and key. Outputs replace the ASG name and autoscaler key with the worker machine configuration, the AMI ID, the instance profile name, and the Karpenter key.
  - `terraform/cluster/`: an availability zone list replaces `aws_availability_zone`; `doppler.tf` writes `KARPENTER_AWS_*`, `AWS_WORKER_MACHINE_CONFIG`, and `AWS_WORKER_AMI_ID` instead of `AUTOSCALER_AWS_*`.
  - `terraform/platform/`: new Karpenter CRD, controller, and node configuration releases and the credential Secret.
  - `terraform/foundation/`: CI IAM policies.
- **Charts:** new `apps/components/karpenter` and `apps/components/karpenter-nodes`; remove `apps/components/cluster-autoscaler`; remove `burst-node-gc` from `apps/components/talos-ccm`; remove the `cluster-autoscaler` entry from `apps/argocd/platform/values.yaml`. `burst-policy` is unchanged.
- **Doppler:** `KARPENTER_AWS_ACCESS_KEY_ID`, `KARPENTER_AWS_SECRET_ACCESS_KEY`, `AWS_WORKER_MACHINE_CONFIG`, and `AWS_WORKER_AMI_ID` replace `AUTOSCALER_AWS_*`.
- **CI:** no workflow changes; `lint.yml` already lints every chart under `apps/components/`. The destroy path relies on the platform root's teardown order.
- **Docs:** `docs/architecture/hybrid-aws-workers.md`, `docs/operations/aws-burst-workers.md`, `docs/reference/secrets.md`, `docs/architecture/gitops.md`, and `CONTRIBUTING.md`.
