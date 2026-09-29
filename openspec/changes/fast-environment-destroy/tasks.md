## 1. Karpenter controller policy

- [x] 1.1 Change the `ListKarpenterInstanceProfiles` resource in `terraform/aws/iam/karpenter-policy.json` to `arn:aws:iam::ACCOUNT_ID:instance-profile/karpenter/REGION/CLUSTER/*`; verify `tofu validate` in `terraform/cluster` passes and the rendered policy in a dev plan shows only that resource changing
- [x] 1.2 Allow `iam:GetInstanceProfile` on `instance-profile/*CLUSTER_*` in `ReadWorkerInstanceProfile`, which the finalizer calls for the managed profile name after listing; verify with `aws iam simulate-custom-policy` that dev names are allowed and prod names denied

## 2. AWS-side sweep in the cluster root

- [x] 2.1 Add `terraform_data.karpenter_sweep` in `terraform/aws/` with `input` holding the region and cluster name, `depends_on` the subnets, worker security group, internet gateway, and worker instance profile, and a destroy-time `local-exec` inline heredoc implementing the loop from design.md (list, terminate, wait, repeat for at least 60 seconds, fail after 15 minutes, then delete launch templates); verify `tofu validate` passes and `shellcheck` accepts the extracted heredoc
- [x] 2.2 Add `depends_on = [terraform_data.karpenter_sweep]` to `aws_iam_user_policy_attachment.karpenter`; verify with `tofu graph -type=plan-destroy` in `terraform/cluster` that the attachment is destroyed before the sweep and the sweep before the subnets, security group, internet gateway, and instance profile
- [x] 2.3 Verify a dev `tofu plan` shows only the sweep resource being created and the policy update, with no replacement of network, IAM, or Proxmox resources

## 3. CI permissions

- [x] 3.1 Add `ec2:DescribeInstances` and `ec2:DescribeLaunchTemplates` to `ReadInfrastructure`, and a statement allowing `ec2:TerminateInstances` and `ec2:DeleteLaunchTemplate` on `instance/*` and `launch-template/*` only with `aws:ResourceTag/managed-by=talos-proxmox` and a present `aws:ResourceTag/karpenter.sh/nodepool`, in `terraform/foundation/ci-policy.json`; verify `tofu validate` in `terraform/foundation` passes and the policy contains no `RunInstances`, `CreateFleet`, or `CreateLaunchTemplate`
- [x] 3.2 Apply the foundation root locally; verify with `aws iam simulate-principal-policy` against the CI role that terminating an instance tagged `managed-by=talos-proxmox` and `karpenter.sh/nodepool` is allowed, and that `RunInstances` and terminating an untagged instance are denied

## 4. Provisioning workflow

- [x] 4.1 In `.github/workflows/provision.yml`, remove the "Destroy platform" step and add a "Reset platform state" step after "Cluster", run only on destroy, that initializes `terraform/platform` with `TF_WORKSPACE=talos-platform-<env>` and removes every address from `tofu state list` when the list is non-empty; verify `actionlint` and the existing lint workflow pass
- [x] 4.2 Verify `tofu state rm` works without a reachable cluster or a Doppler `KUBECONFIG` by running `tofu state list` and a dry run of the reset against a scratch copy of the dev platform state; if it evaluates configuration and fails, switch the step to `tofu state push` of an empty state as in design.md

## 5. Documentation

- [x] 5.1 Rewrite "Destroy an environment with running workers" in `docs/operations/aws-burst-workers.md` for the cluster-root sweep, the platform state reset, and the steps for a local destroy; verify the procedure no longer mentions the NodePool drain wait
- [x] 5.2 Update the ownership rationale in `docs/architecture/hybrid-aws-workers.md` (Karpenter is no longer in the platform root for teardown order) and the CI permission sentence; update the destroy order in `docs/architecture/terraform-ci.md`; verify neither doc says destroy runs the platform root first
- [x] 5.3 Add the rule to `docs/architecture/gitops.md` that the platform root and Argo CD components must not create resources outside the cluster that need removal on destroy; verify the ownership table and the new rule agree

## 6. Rollout and validation

- [ ] 6.1 Merge to `main` and let the push-triggered apply run for dev and prod; verify both applies succeed (rerun the platform apply once if `karpenter-nodes` races the old node class), `kubectl get ec2nodeclass` shows a fresh `aws-burst`, and the Karpenter logs have no `ListInstanceProfiles` `AccessDenied`
- [ ] 6.2 Run the Manual Provision destroy on dev with no AWS workers; verify it finishes without a "Destroy platform" step, `tofu state list` in `talos-platform-dev` is empty, and no instance or launch template tagged `kubernetes.io/cluster/dev-talos=owned` remains
- [ ] 6.3 Apply dev, start a burst workload so at least one AWS worker is running, and run the destroy again; verify the sweep terminates the worker in minutes rather than draining it, the VPC is removed, and no dev instance or launch template remains
- [ ] 6.4 Apply dev once more from the emptied platform state; verify the apply succeeds and Argo CD converges as for a fresh environment
- [ ] 6.5 Run `openspec validate fast-environment-destroy --strict` and verify it passes
