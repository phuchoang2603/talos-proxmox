## 1. AWS infrastructure (cluster root)

- [x] 1.1 Replace `aws_availability_zone` with an `availability_zones` list in `terraform/aws` and `terraform/cluster`, create one public subnet per zone associated with the public route table, and tag every subnet and the worker security group `karpenter.sh/discovery=<cluster>`; verify with `tofu validate` and a dev plan showing four subnets.
- [x] 1.2 Remove the Auto Scaling Group, the launch template, and the `k8s.io/cluster-autoscaler/*` tags from `terraform/aws/main.tf`, and add `karpenter.sh/unregistered=true:NoExecute` to the worker `register-with-taints`; verify `rg 'cluster-autoscaler|aws_autoscaling_group|aws_launch_template' terraform/` returns nothing.
- [x] 1.3 Add the `<env>-talos-burst-worker` IAM role (EC2 trust, no policies) and instance profile; verify a dev plan shows no policy attachments on the role.
- [x] 1.4 Replace the autoscaler IAM user, policy, and key with `talos-proxmox-karpenter-<env>` and `terraform/aws/iam/karpenter-policy.json` as scoped in design.md; verify the rendered policy JSON has no `ENV`, `CLUSTER`, or `ACCOUNT_ID` placeholders left and that every mutating statement has a cluster tag, discovery tag, AMI, or named-resource restriction.
- [x] 1.5 Change the AWS module outputs to the worker machine configuration (sensitive), the AMI ID, the instance profile name, and the Karpenter key, and change `terraform/cluster/doppler.tf` to write `KARPENTER_AWS_*`, `AWS_WORKER_MACHINE_CONFIG`, and `AWS_WORKER_AMI_ID` instead of `AUTOSCALER_AWS_*`; verify the dev plan shows those values only as sensitive.
- [x] 1.6 Update `terraform/foundation/ci-policy.json` and `ci-iam-policy.json` as described in design.md (drop ASG, launch template, and `RunInstances`; add `DescribeAvailabilityZones`; manage the Karpenter user and policy and the worker role and profile; `PassRole` only for the worker role to EC2); verify with a foundation plan and a dev cluster plan run under the CI role.

## 2. Karpenter charts

- [x] 2.1 Choose the newest Karpenter release whose compatibility matrix includes Kubernetes 1.36, and vendor its `karpenter-crd` chart as `apps/components/karpenter-crd`; verify `helm lint --kube-version 1.36.3` passes and the chart renders the `NodePool`, `NodeClaim`, and `EC2NodeClass` CRDs.
- [x] 2.2 Create the `apps/components/karpenter` wrapper chart with values for the control-plane `nodeSelector` and toleration, no zone topology spread, `controller.env` credentials from `karpenter-aws` plus `AWS_REGION`, no interruption queue, and replicas of 1 in dev and 2 in prod; verify `helm lint` passes for the base values and the prod overlay, and `helm template` shows the expected replicas per environment.
- [x] 2.3 Create `apps/components/karpenter-nodes` rendering the `EC2NodeClass` and `aws-burst` `NodePool` from design.md, with lint-safe placeholder `userData`, AMI, cluster name, and instance profile; verify `helm lint` passes and `helm template` shows `amiFamily: Custom`, both capacity types, the burst label and taint, both startup taints, the limits, and the disruption settings.

## 3. Platform root

- [x] 3.1 Add `terraform/platform/karpenter.tf` with `kubernetes_secret_v1.karpenter_aws` and releases `karpenter_crd`, `karpenter` (CRDs skipped, cluster name and endpoint set, key checksum annotation) and `karpenter_nodes` (`set_sensitive` userData, `wait = true`, a timeout longer than `terminationGracePeriod`), in the dependency order from design.md; verify `tofu validate` and a dev plan that shows the machine configuration and key only as sensitive.

## 4. Remove Cluster Autoscaler and node cleanup

- [x] 4.1 Delete `apps/components/cluster-autoscaler` and its entry in `apps/argocd/platform/values.yaml`; verify `helm lint` of the Argo CD platform chart for dev and prod and that `rg -i 'cluster-autoscaler' apps/` returns nothing.
- [x] 4.2 Remove `burst-node-gc` from `apps/components/talos-ccm` (template, values, comment); verify `helm template` renders only the CCM resources.

## 5. Dev spike and validation (from an operator machine, before merge)

- [x] 5.1 Apply the cluster and platform roots locally against the dev workspaces; verify the Karpenter pod is Ready on the control plane, logs show no `AccessDenied`, and Doppler accepts `AWS_WORKER_MACHINE_CONFIG` (if it is rejected, switch that hand-off to `tfe_outputs` and update design.md).
- [x] 5.2 Scale a stateless burst Deployment from zero; verify a NodeClaim reaches `Registered`, `Initialized`, and `Ready`, the Node has an `aws:///` provider ID, the burst label and taint, and no `karpenter.sh/unregistered` or startup taints remaining, and the pod runs on it over KubeSpan.
- [x] 5.3 Compare Karpenter's predicted allocatable on the NodeClaim with the Node's real allocatable for each instance size launched, and tune the EC2NodeClass `kubelet` block until the prediction is at or below the real value; verify with a pod sized to the predicted allocatable, which must schedule on the first node.
- [x] 5.4 Verify the stateless-only policy still holds: a PVC-backed pod that tolerates the burst taint is rejected, and an `emptyDir` pod schedules on AWS.
- [ ] 5.5 (consolidation to zero verified on dev; console-termination check still to do) Scale the Deployment to zero and verify consolidation terminates the worker and removes its Node within about ten minutes; terminate a worker from the AWS console and verify its NodeClaim and Node are removed and a replacement is launched for the pending pods.
- [x] 5.6 Change a value that affects `userData` (for example a harmless Talos patch) and verify Karpenter marks the running worker as drifted and replaces it.
- [ ] 5.7 Run a local platform destroy on dev with a worker running; verify the NodeClaims and EC2 instances are gone and the Karpenter launch templates are deleted before the controller release is removed, then re-apply the platform.
- [ ] 5.8 Verify the dev Karpenter key cannot terminate a prod-tagged instance or launch into a prod subnet, with an IAM policy simulator run or a direct denied call.

## 6. Documentation

- [x] 6.1 Rewrite `docs/architecture/hybrid-aws-workers.md` for Karpenter (topology, scale-from-zero and consolidation, spot without an interruption queue, drift, ownership, credential scope, known limits); verify its links resolve and it does not mention the ASG or Cluster Autoscaler.
- [ ] 6.2 Rewrite `docs/operations/aws-burst-workers.md` (schedule a workload, observe NodeClaims, pause bursting by setting limits to zero, key rotation through cluster and platform applies, safe teardown); verify every command has been run against dev.
- [x] 6.3 Update `docs/reference/secrets.md`, `docs/architecture/gitops.md` (Karpenter owned by the platform root; the second platform-owned Secret), and `CONTRIBUTING.md` (lint commands, generated secrets, destroy); verify `rg -i 'autoscaler|AUTOSCALER_' docs CONTRIBUTING.md README.md` shows only intended references.

## 7. Rollout

- [x] 7.1 Merge to `main` and verify the CI applies for dev and prod succeed, Argo CD prunes the `cluster-autoscaler` application and the `burst-node-gc` resources, and no ASG named `*-talos-burst` remains in AWS.
- [x] 7.2 Repeat the burst-from-zero and return-to-zero checks (5.2 and 5.5) on prod.
