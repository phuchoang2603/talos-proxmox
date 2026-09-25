## Context

See `proposal.md` for motivation and `specs/hybrid-aws-burst-workers/spec.md` for behavior. `terraform/cluster/` manages fixed Proxmox VMs and stateless AWS burst workers with separate MinIO state keys `talos-${env}.tfstate` for argocd, dev, and prod. `terraform/identity/` manages the GitHub OIDC CI role in independent local state. Doppler’s `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are **MinIO** credentials, not AWS IAM credentials. Dev uses local-path; prod uses Longhorn. Cilium enables WireGuard and LAN-only L2 announcements. The argocd cluster manages applications on dev and prod.

## Goals / Non-Goals

**Goals:**

- Keep fixed Proxmox clusters and add stateless burst capacity on AWS.
- Keep one MinIO state per environment and keep infrastructure and application configuration in Git.
- Lint PRs without secrets and apply only from `main` using GitHub OIDC for AWS access.

**Non-Goals:**

- EBS CSI, `gp3`, any AWS PVCs, Longhorn engines/replicas on AWS, or durable node-local AWS data.
- Omni, Cluster API, Karpenter, EKS, GCP, and persistent AWS storage.

## Decisions

### Cluster and identity roots

`terraform/cluster/` is the cluster root, selecting an environment and calling `terraform/proxmox/` for fixed VMs and `terraform/aws/` for stateless workers. It uses a separate MinIO backend key `talos-${env}.tfstate` per environment. AWS workers are created only for dev/prod; argocd is Proxmox-only. Each AWS module instance owns its environment's VPC, public subnet, internet gateway, route table, bounded ASG, and autoscaler IAM user and policy. Dev uses `10.80.0.0/16` and prod uses `10.81.0.0/16`; neither uses the default VPC. An internet gateway and public instance address allow KubeSpan discovery and UDP 51820 without a public Kubernetes API. Desired capacity belongs to Cluster Autoscaler. A single AZ per environment keeps the compute configuration simple.

`terraform/identity/` is a separate local-state root for the GitHub OIDC provider, CI role, and its scoped infrastructure and IAM delegation policies (`ci-policy.json` and `ci-iam-policy.json`). The cluster root does not consume identity state or outputs. CI references the role ARN in the workflow. It can manage only the named autoscaler IAM resources and project-tagged network resources needed by the dev/prod AWS modules; it does not own their state.

### GitHub OIDC, distinct from MinIO

Use Doppler `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` exclusively for the MinIO S3 backend. Provision a GitHub OIDC provider and scoped CI role from a separate local OpenTofu identity root, independently of cluster deployment. Restrict the AWS trust policy to the repository's dev/prod environment subjects and restrict those GitHub Environments to `main`. CI assumes the role only during main provisioning; pass its short-lived access key, secret, and session token into ephemeral AWS provider variables while Doppler injects only MinIO keys for the S3 backend. EC2 and Auto Scaling Describe operations remain account-wide. Do not commit or print credentials, and do not upload saved plans. Argocd requires no AWS session.

Cluster Autoscaler stays on fixed Proxmox nodes so AWS workers can scale to zero. Each `terraform/aws/` instance provisions its environment's IAM user and ASG-scoped policy. Access keys are created outside Terraform, stored in the matching Doppler config as `AUTOSCALER_AWS_ACCESS_KEY_ID` and `AUTOSCALER_AWS_SECRET_ACCESS_KEY`, and copied into the cluster's `cluster-autoscaler-aws` Secret during bootstrap. Keys do not enter Git or Terraform state. The Argo-managed chart remains disabled until AWS nodes reliably register with a burst taint, label, and AWS provider ID and the PVC admission checks pass. The autoscaler must not use the broader CI role or MinIO credentials.

### PR lint and main apply

Lint both OpenTofu roots and platform charts on PRs without Doppler secrets, state access, or AWS credentials. Only `main` pushes plan and apply all three cluster environments; manual apply/destroy is gated to `main`. No merge protection or required status checks are assumed. Never use `pull_request_target` to run PR code. Main plans are saved only on ephemeral runners and are not uploaded.

### KubeSpan and stateless capacity

Enable KubeSpan on fixed dev/prod Talos nodes and AWS workers using the provider-supported `machine.network.kubespan` field and discovery service. Keep the current private VIP as the cluster endpoint for LAN clients and the separate Argo CD cluster; do not publish TCP 6443 to AWS. Talos KubePrism on each AWS worker (localhost:7445, already used by Cilium) must discover and connect to healthy control-plane nodes over KubeSpan even though the VIP is unreachable from AWS. The VIP remains KubePrism fallback, not the required worker path. Give at least one end of each cross-site link inbound UDP 51820 (prefer the AWS worker) and outbound discovery access; detect NotReady workers and test pod/Service connectivity, effective MTU, and nested Cilium WireGuard behavior in both dev and prod. If KubeSpan bootstrap cannot reliably establish a healthy API path, add a private reachable API load balancer or gateway as a separate design change rather than silently exposing the API. Prevent AWS nodes from advertising Proxmox L2 service IPs; validate prod API failover. Deploy compatible AWS Cluster Autoscaler via Argo CD on fixed Proxmox capacity with ASG scale-from-zero node labels, taints, capacity, provider ID and least-privilege AWS credentials. An AWS `NoSchedule` taint and positive workload affinity make burst placement explicit; test 0→1→0 with no EBS/Longhorn dependency.

### Proxmox-only PVCs

Dev keeps local-path as its sole default, prod keeps Longhorn as its sole default, and both provision PVCs only for pods pinned to fixed Proxmox nodes. Do **not** deploy EBS CSI or a gp3 StorageClass. An EC2 instance may still have an EBS-backed boot disk; it is disposable machine storage, not a Kubernetes PV/PVC. Exclude AWS workers from Longhorn system/replica scheduling and ensure dev local-path PV users remain on Proxmox. AWS-opted-in application manifests contain no PVC volume or volumeClaimTemplates and can use only disposable `emptyDir` for scratch. Enforce this through the AWS taint, app affinity, and workload validation/admission that rejects PVC-bearing pods eligible for the AWS taint, including wildcard tolerations. Keep a positive on-premises placement requirement for every Git-managed PVC workload. Verify these constraints on both dev and prod rather than assuming storage replica placement also restricts workloads.

## Risks / Trade-offs

- [Environment-scoped OIDC subjects omit the branch] → Restrict dev/prod GitHub Environments to `main` and lint PRs without deployment secrets.
- [One cluster root spans two providers] → Keep separate per-environment MinIO state keys; pass short-lived AWS provider credentials separately from MinIO backend credentials.
- [KubeSpan discovery or UDP reachability, KubePrism fallback to unreachable VIP, double encapsulation, Cilium device detection] → Require AWS-worker readiness and KubePrism upstream tests with VIP blocked, plus cross-site node/pod/API connectivity and MTU checks in dev and prod.
- [Unexpected PVC pod on AWS] → A dev worker joined Ready without its Talos-configured label, taint, or provider ID in the initial September 25, 2026 test. Keep the autoscaler disabled while validating kubelet registration taints, provider ID assignment, positive on-prem affinity, and admission of PVC-bearing and wildcard-tolerating workloads.

## Rollout

1. Verify PR lint and the main-only OIDC provisioning workflow.
2. Verify KubeSpan/KubePrism connectivity, Cilium networking, and storage placement with bounded dev/prod worker groups at desired capacity zero.
3. Provision a separate autoscaler identity before enabling Argo-managed autoscaling. Test stateless 0→1→0 scaling in dev and prod. Roll back burst capacity by draining and scaling workers to zero.
