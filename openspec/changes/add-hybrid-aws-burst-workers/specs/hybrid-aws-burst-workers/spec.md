## Purpose

Provide optional stateless AWS compute capacity to Talos clusters, keeping persistent Kubernetes workloads on fixed on-premises nodes.

## ADDED Requirements

### Requirement: Fixed Proxmox capacity
The platform SHALL maintain Talos control planes and on-premises storage and GPU nodes as fixed Proxmox VMs. Cluster identity and credentials SHALL be shared by each environment’s fixed nodes and AWS workers. Scaling AWS workers MUST NOT change the fixed Proxmox inventory.

#### Scenario: Add AWS worker capacity
- **WHEN** AWS burst infrastructure is deployed to an environment
- **THEN** it joins the cluster without changing fixed Proxmox capacity or requiring persistent volumes

### Requirement: Bounded, independently autoscaled AWS workers
The platform SHALL add Talos worker nodes to the dev and prod clusters from AWS within environment-specific minimum and maximum bounds, including a zero-worker idle state. AWS scaling MUST NOT change the fixed Proxmox inventory, and in-cluster scaling control MUST remain available when the AWS worker count is zero.

#### Scenario: Burst from zero
- **WHEN** an eligible pending workload requires AWS capacity and the AWS worker count is zero
- **THEN** an AWS worker joins the cluster and can run that workload within the configured maximum

#### Scenario: Return to zero
- **WHEN** AWS workers host no non-evictable workloads and the scale-down delay has elapsed
- **THEN** the AWS worker group can return to zero while Proxmox nodes and scaling control remain available

#### Scenario: Reach capacity limit
- **WHEN** eligible pending workloads require more nodes than the configured AWS maximum
- **THEN** the worker count does not exceed that maximum and the excess workloads remain visibly pending

### Requirement: Hybrid node and pod connectivity
The platform SHALL connect AWS workers to Proxmox control planes through KubeSpan, use KubePrism on each AWS worker to reach discovered control-plane nodes through that mesh, and support bidirectional pod and node communication. The Kubernetes API VIP SHALL remain private and available to on-premises clients and the separate Argo CD cluster. No public Kubernetes API endpoint is required for AWS workers. If KubeSpan or KubePrism cannot reach a control plane, AWS workers MUST remain unready rather than silently scheduling applications on a broken network.

#### Scenario: Join across networks
- **WHEN** an AWS Talos worker boots with its rebuilt environment's cluster identity
- **THEN** it discovers Proxmox peers through KubeSpan, connects to a control plane through local KubePrism, becomes Ready, and exchanges pod traffic with on-premises nodes

#### Scenario: Private LAN VIP is unreachable from AWS
- **WHEN** an AWS worker cannot route to the Proxmox-only Kubernetes API VIP
- **THEN** it uses discovered control-plane addresses via KubeSpan and its local KubePrism proxy, without exposing the API publicly

#### Scenario: Mesh or API proxy cannot establish a healthy path
- **WHEN** peer discovery, UDP KubeSpan connectivity, or the local KubePrism upstreams fail
- **THEN** the AWS worker remains NotReady and the failure is observable before burst workloads are scheduled

### Requirement: Persistent storage remains on fixed Proxmox nodes
The platform SHALL retain `local-path` as the sole default StorageClass in dev and Longhorn as the sole default StorageClass in prod. PVC-backed workloads in either environment MUST run on fixed Proxmox nodes. The platform MUST NOT provision an AWS EBS CSI driver, `gp3` StorageClass, or Longhorn replica disks on autoscaled AWS workers.

#### Scenario: Default dev claim
- **WHEN** a dev workload requests a PVC without a StorageClass
- **THEN** it receives local-path storage and runs on a fixed Proxmox node

#### Scenario: Default prod claim
- **WHEN** a prod workload requests a PVC without a StorageClass
- **THEN** it receives Longhorn storage and runs on a fixed Proxmox node

#### Scenario: AWS worker scales up
- **WHEN** a new AWS worker registers in dev or prod
- **THEN** no persistent volume provisioner or Longhorn replica storage is enabled on that worker

### Requirement: AWS burst capacity is stateless only
The platform SHALL allow AWS workers to run only explicitly opted-in workloads without PVCs or persistent-volume templates. AWS workloads MAY use disposable `emptyDir` scratch space; it MUST NOT be presented as persistent data. The platform MUST keep PVC-backed pods on Proxmox even if they request AWS capacity.

#### Scenario: Stateless workload bursts
- **WHEN** a pod without PVC dependencies explicitly opts into AWS worker capacity
- **THEN** it can schedule on an AWS worker and can be rescheduled without retaining node-local data

#### Scenario: PVC-backed workload requests AWS capacity
- **WHEN** a dev local-path or prod Longhorn workload has a PVC and otherwise qualifies for AWS burst capacity
- **THEN** it cannot schedule on AWS and remains on fixed Proxmox capacity or visibly Pending

#### Scenario: AWS worker terminates
- **WHEN** an autoscaled AWS worker hosting a stateless workload is removed
- **THEN** its disposable scratch contents may be lost without deleting any persistent cluster data

### Requirement: Secure, Git-managed reconciliation
The platform SHALL manage Proxmox and AWS infrastructure in one root with a separate MinIO state key per cluster environment, and reconcile in-cluster autoscaling, storage drivers, and storage policies from Git. It MUST protect Talos identities and bootstrap material and cloud credentials from repository disclosure, use different credentials for MinIO state, AWS provisioning, and on-premises autoscaling, and prevent infrastructure reconciliation from overwriting the autoscaler's desired worker count.

#### Scenario: Reconcile the AWS infrastructure
- **WHEN** Git-managed infrastructure changes are applied while the autoscaler owns worker capacity
- **THEN** worker count remains within declared bounds without an unrelated reset of the autoscaler's chosen desired capacity

#### Scenario: Inspect repository and pipeline logs
- **WHEN** a user reads committed configurations or routine CI output
- **THEN** Talos cluster secrets, AWS credentials, and machine bootstrap configurations are not exposed in plaintext

#### Scenario: Distinct AWS access from CI and autoscaler
- **WHEN** CI plans/provisions AWS infrastructure and the on-premises autoscaler adjusts its AWS worker group
- **THEN** neither process authenticates to AWS with the MinIO backend key, and the autoscaler cannot use the broader CI provisioning credential

### Requirement: Lint PRs and provision from main only
The platform SHALL lint both OpenTofu roots and platform charts on pull requests targeting `main` without exposing state, AWS credentials, or Doppler environment secrets. Only a push or explicitly dispatched workflow on `main` SHALL plan and apply changes. AWS access in CI MUST use a scoped GitHub OIDC role, separate from MinIO backend keys; the on-premises autoscaler SHALL have separate scaling-only credentials before it is enabled.

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** the OpenTofu roots and platform charts are linted without accessing remote state or deployment secrets

#### Scenario: Push to main
- **WHEN** reviewed changes are pushed to `main`
- **THEN** all three environments generate fresh plans and apply through their protected apply environments

#### Scenario: Manual run from another branch
- **WHEN** a manual workflow dispatch targets a ref other than `main`
- **THEN** no infrastructure apply or destroy job runs
