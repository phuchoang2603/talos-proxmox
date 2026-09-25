## Context

See `proposal.md` for motivation and `specs/hybrid-aws-burst-workers/spec.md` for behavior. `terraform-provision/` currently owns fixed Proxmox VMs, generates Talos cluster secrets, and uses MinIO key `talos-${env}.tfstate` for each of argocd, dev, and prod. CI uses Doppler's `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` for **MinIO**, not AWS IAM. Dev uses local-path; prod uses Longhorn. Cilium enables WireGuard and LAN-only L2 announcements. The existing argocd cluster manages applications on dev and prod.

The PR workflow uses the existing environments and `borchero/terraform-plan-comment@v2`. Destroy the current clusters through the remote workflow on `main` before switching CI to OpenTofu; the new configuration is a clean rebuild, not a state or identity migration.

## Goals / Non-Goals

**Goals:**

- Recreate fixed Proxmox clusters with new identities and add stateless burst capacity on AWS; old PVC data is not retained.
- Keep one MinIO state per environment and keep infrastructure and application configuration in Git.
- Reuse existing GitHub Environments for PR plans/comments and main-only applies, without AWS OIDC setup.

**Non-Goals:**

- EBS CSI, `gp3`, any AWS PVCs, Longhorn engines/replicas on AWS, or durable node-local AWS data.
- Omni, Cluster API, Karpenter, EKS, GCP, old state migration, and PVC preservation.

## Decisions

### One root and clean rebuild

After all three remote destroys succeed, replace `terraform-provision/` with `terraform/cluster/` as the single root selected by `env`; organize fixed VMs in `terraform/proxmox` and burst capacity in `terraform/aws`. Reuse the separate MinIO backend keys `talos-${env}.tfstate` only after old resources are destroyed; no `state mv`, import, no-replacement plan, or retention of old Talos secrets is needed. Generate a fresh Talos identity for each environment and use it for its fixed nodes and AWS workers. Add AWS workers only for dev/prod; argocd stays Proxmox-only. Do not reuse Proxmox static IP, installer or GPU patches on AWS. Cap ASG min/max while leaving desired capacity to Cluster Autoscaler. Start with a small single-AZ worker pool in each environment for simplicity, not for PVC topology.

Pin a verified stable OpenTofu release in `devenv.nix` and CI when implementing the new root. Switch CI directly from the old destroyed Terraform root to the new OpenTofu root, including the PR comment action's plan-file handling; verify the plugin accepts OpenTofu plans before enabling main applies. Do not push a half-converted workflow to `main`, since that branch triggers apply for all three environments.

Alternative: separate AWS/Proxmox roots require sharing Talos machine secrets outside the per-environment state and increase workflow complexity for these clusters.

### Static AWS IAM credentials, distinct from MinIO

Keep existing Doppler `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` exclusively for the MinIO S3 backend. Create a narrowly scoped AWS IAM user for CI infrastructure provisioning (restrict mutating calls to project-owned resources; EC2 and Auto Scaling Describe operations are account-wide, so do not claim unrelated resources are unreadable) and store its **different** access key as `AWS_PROVIDER_ACCESS_KEY_ID` / `AWS_PROVIDER_SECRET_ACCESS_KEY` in the existing dev/prod Doppler configs. In OpenTofu, map these only to explicit AWS provider arguments via `sensitive = true, ephemeral = true` root variables. Do not commit or print keys; validate that the saved PR plan, MinIO state, and plan comment omit the provider keys. Because `tofu apply .planfile` needs ephemeral inputs again, the existing CI credential wrapper must supply them to both plan and apply. Argocd requires no AWS provider credentials.

Cluster Autoscaler stays on fixed Proxmox nodes so AWS workers can scale to zero. An AWS EC2 instance profile cannot authenticate this on-premises pod. Create a **separate** IAM user/key limited to describing the AWS worker groups and changing capacity of only the tagged ASGs. Store that key in Doppler and deliver it as a Kubernetes Secret at bootstrap without committing it; Argo CD manages the autoscaler chart and references the secret. Document key rotation and revoke unused keys. One CI key can be reused across the two environments if its AWS policy and trust boundary are appropriate; no GitHub OIDC provider or roles are required. Be explicit that PRs using existing per-environment Doppler tokens can access both MinIO state and the CI AWS key: restrict plans to trusted same-repository PRs and review code before running them. A read-only PR key or OIDC would harden this later but is not required for the requested minimal design.

Alternative: GitHub OIDC avoids a static CI key but adds provider/role bootstrap and separate trust policies for PR versus main. Using MinIO keys as AWS provider credentials is incorrect, regardless of authentication choice.

### PR plan and main apply

On each trusted PR targeting `main`, lint and plan argocd, dev and prod against their emptied state keys and post a uniquely headed comment for each environment with the existing plugin; keep saved plans only on the ephemeral runner. Only `main` pushes apply all three environments after a fresh plan. Manual apply/destroy is gated to `main`. Branch rules select the required lint and three plan statuses; workflow YAML cannot make status checks required. Never use `pull_request_target` to run PR code. The AWS provider key and Talos machine secrets require PR code trust and comment-content review even though the regular rendered plan normally hides sensitive fields.

### KubeSpan and stateless capacity

Enable KubeSpan on fixed dev/prod Talos nodes and AWS workers using the Talos 1.13-compatible (deprecated) `machine.network.kubespan` field and discovery service; the pinned Talos Terraform provider v0.9.0 embeds Talos v1.11 and rejects `KubeSpanConfig` in config patches, so migrate to that document only after upgrading the provider and validating all machine configs. Keep the current private VIP as the cluster endpoint for LAN clients and the separate Argo CD cluster; do not publish TCP 6443 to AWS. Talos KubePrism on each AWS worker (localhost:7445, already used by Cilium) must discover and connect to healthy control-plane nodes over KubeSpan even though the VIP is unreachable from AWS. The VIP remains KubePrism fallback, not the required worker path. Give at least one end of each cross-site link inbound UDP 51820 (prefer the AWS worker) and outbound discovery access; detect NotReady workers and test pod/Service connectivity, effective MTU, and nested Cilium WireGuard behavior in both dev and prod. If KubeSpan bootstrap cannot reliably establish a healthy API path, add a private reachable API load balancer or gateway as a separate design change rather than silently exposing the API. Prevent AWS nodes from advertising Proxmox L2 service IPs; validate prod API failover. Deploy compatible AWS Cluster Autoscaler via Argo CD on fixed Proxmox capacity with ASG scale-from-zero node labels, taints, capacity, provider ID and least-privilege AWS credentials. An AWS `NoSchedule` taint and positive workload affinity make burst placement explicit; test 0→1→0 with no EBS/Longhorn dependency.

### Proxmox-only PVCs

Dev keeps local-path as its sole default, prod keeps Longhorn as its sole default, and both provision PVCs only for pods pinned to fixed Proxmox nodes. Do **not** deploy EBS CSI or a gp3 StorageClass. An EC2 instance may still have an EBS-backed boot disk; it is disposable machine storage, not a Kubernetes PV/PVC. Exclude AWS workers from Longhorn system/replica scheduling and ensure dev local-path PV users remain on Proxmox. AWS-opted-in application manifests contain no PVC volume or volumeClaimTemplates and can use only disposable `emptyDir` for scratch. Enforce this through the AWS taint, app affinity, and workload validation/admission that rejects PVC-bearing pods eligible for the AWS taint, including wildcard tolerations. Keep a positive on-premises placement requirement for every Git-managed PVC workload. Verify these constraints on both dev and prod rather than assuming storage replica placement also restricts workloads.

## Risks / Trade-offs

- [Static AWS keys in CI and cluster] → Dedicated restricted users for provisioning versus ASG scaling, Doppler/Kubernetes Secret storage, rotation, and no secrets in Git, state, or PR comments.
- [Trusted PR code can use existing write-capable environment secrets] → Reject forks, review same-repository PR code and optional environment approvals; note that a static CI key does not isolate PR read access from main writes.
- [One root spans both providers] → Keep separate per-env MinIO state keys and review plans for all environments before enabling main apply.
- [KubeSpan discovery or UDP reachability, KubePrism fallback to unreachable VIP, double encapsulation, Cilium device detection] → Require AWS-worker readiness and KubePrism upstream tests with VIP blocked, plus cross-site node/pod/API connectivity and MTU checks in dev and prod.
- [Unexpected PVC pod on AWS] → Opt-in taint, positive on-prem affinity, and validation/admission of PVC-bearing and wildcard-tolerating workloads before scaling.

## Rebuild Plan

1. Dispatch and verify `destroy` for argocd, dev, and prod using the existing remote GitHub Actions workflow; accept loss of existing cluster identities and PVC data. Do not push a main-branch apply while the old workflow remains.
2. Replace the old root with `terraform/cluster/` and `terraform/proxmox` and `terraform/aws` modules; configure pinned OpenTofu in devenv and CI and reuse the emptied per-environment MinIO keys without importing old state. Check PR plans/comments against the new root before a main apply.
3. Create CI and autoscaler IAM users/least-privilege policies, store separate keys in existing Doppler configs and bootstrap an on-premises autoscaler Secret. Do not add AWS resources before credential separation and PR safety are verified.
4. Recreate argocd, dev, and prod fixed clusters from Git with new Talos identities. Keep their private VIPs, configure KubeSpan and KubePrism for dev/prod AWS workers, and verify networking and storage placement in both environments; there is no dev-only migration gate.
5. Enable the dev and prod stateless AWS ASGs and Argo-managed autoscaler with bounded workers. Verify pod/API connectivity, prod API failover, Longhorn/system placement, and 0→1→0 scaling in both clusters. Roll back burst capacity by draining/scaling AWS to zero; old cluster state and PVC data cannot be recovered by this rollback.
