## MODIFIED Requirements

### Requirement: Fixed Proxmox capacity
Dev SHALL use fixed Proxmox VMs: pve with 8 CPU/32 GiB and GPU as control plane and worker, pve2 with 8 CPU/16 GiB and pve3 with 4 CPU/16 GiB as workers. Prod SHALL use an independent AWS Talos cluster with one On-Demand m6a.xlarge control-plane/workload node and one On-Demand m6a.xlarge worker in one AZ. Dev SHALL also have its own zero-baseline AWS Spot CPU pool joining the Proxmox Talos identity over KubeSpan. Cluster identities MUST be independent.

#### Scenario: Fresh deployment
- **WHEN** both environments are applied
- **THEN** dev preserves those VM allocations and prod has no dependency on Proxmox

#### Scenario: Add AWS worker capacity
- **WHEN** production AWS workers are provisioned
- **THEN** they join the independent production identity and leave dev Proxmox allocations unchanged

### Requirement: Bounded, independently autoscaled AWS workers
Karpenter SHALL be the sole provisioner for CPU and optional GPU workers. Prod SHALL maintain one On-Demand m6a.xlarge CPU worker with at most one extra baseline replacement node and one additional demand-driven Spot worker. The prod controller SHALL run on the On-Demand control plane. Dev SHALL run its own controller on the Proxmox control plane and enable only the bounded, demand-driven Spot CPU pool, with separate AWS networking, credentials and interruption resources. The baseline SHALL use On-Demand capacity; the burst CPU pool SHALL use Spot only and return to zero when no longer needed. GPU capacity SHALL be disabled by default and explicitly bounded when enabled. Interruption events SHALL trigger replacement and lost Node cleanup.

#### Scenario: Worker interruption
- **WHEN** a Spot worker is reclaimed
- **THEN** Karpenter attempts replacement in the selected AZ without launching On-Demand workers or exceeding the CPU node bound

#### Scenario: Burst from zero
- **WHEN** production has no CPU workers
- **THEN** Karpenter on the On-Demand control plane attempts to restore one m6a.xlarge On-Demand worker within the baseline node bound

#### Scenario: Return to zero
- **WHEN** CPU workers become idle
- **THEN** the static CPU baseline remains one worker; the optional idle GPU pool can return to zero

#### Scenario: Reach capacity limit
- **WHEN** replacement overlap reaches three CPU workers
- **THEN** no additional CPU worker is launched and excess workloads remain visibly pending

#### Scenario: Spot capacity is reclaimed
- **WHEN** AWS reclaims a Spot worker
- **THEN** Karpenter attempts same-AZ Spot replacement, removes the lost Node and reschedules eligible pods after storage detachment

#### Scenario: Instance is terminated outside the cluster
- **WHEN** an AWS worker instance is terminated from the AWS console or API
- **THEN** its Node object is removed from the cluster without an operator or scheduled job deleting it

### Requirement: Hybrid node and pod connectivity
Each cluster SHALL provide node and pod connectivity within its own network using Cilium and Talos KubePrism. Prod SHALL expose a stable API endpoint restricted to explicit operator/CI CIDRs and internal node access; management APIs MUST NOT allow all IPv4 sources. Prod MUST NOT require a cross-site Proxmox mesh.

#### Scenario: Independent cloud boot
- **WHEN** Proxmox is unavailable
- **THEN** prod workers can join and reach the API and other prod pods

#### Scenario: Join across networks
- **WHEN** a production Talos worker boots
- **THEN** it joins the AWS control plane through same-VPC connectivity and local KubePrism without Proxmox peers

#### Scenario: Private LAN VIP is unreachable from AWS
- **WHEN** a client expects the removed dev API VIP
- **THEN** dev uses its control-plane node address directly and prod uses its independent Elastic IP endpoint

#### Scenario: Mesh or API proxy cannot establish a healthy path
- **WHEN** a worker cannot reach its own control plane through KubePrism
- **THEN** it remains NotReady and the connection failure is observable

### Requirement: Storage follows environment capabilities
Dev SHALL use local-path as its sole default StorageClass. Prod SHALL use encrypted expandable gp3 EBS through CSI with WaitForFirstConsumer as its sole default. Ordinary PVC-backed workloads SHALL be eligible for AWS workers. All CNPG clusters SHALL initially have one instance. Storage SHALL NOT be described as HA.

#### Scenario: Worker replacement with a volume
- **WHEN** an AWS worker with an EBS claim terminates
- **THEN** the same-AZ replacement can attach the existing volume after safe detachment

#### Scenario: Default dev claim
- **WHEN** a dev workload requests a PVC without a StorageClass
- **THEN** it receives node-bound local-path storage; data on a Spot worker remains ephemeral

#### Scenario: Default prod claim
- **WHEN** a prod workload requests a PVC without a StorageClass
- **THEN** it receives encrypted gp3 EBS storage with WaitForFirstConsumer in the selected AZ

#### Scenario: Volume node is unavailable
- **WHEN** a node hosting a volume is unavailable
- **THEN** dev local-path pods wait for their node; prod EBS pods may recover on another same-AZ node after safe detachment

#### Scenario: AWS worker scales up
- **WHEN** a new AWS worker registers in prod
- **THEN** ordinary PVC-backed workloads may schedule there using gp3

### Requirement: Secure, Git-managed reconciliation
Infrastructure SHALL have separate per-environment state and scoped credentials for CI, Karpenter, CSI and object consumers. Worker identities SHALL have no application permissions. Environment destroy SHALL revoke Karpenter scale-out, terminate owned workers and delete launch templates before removing network resources, using AWS APIs even if Kubernetes is unavailable. Data retention and purge SHALL be explicit. Secrets MUST NOT appear in Git or routine logs.

#### Scenario: Offline destroy
- **WHEN** the Kubernetes API is down during destroy
- **THEN** AWS-owned compute and declared external resources are cleaned according to retention policy before platform state is reset

#### Scenario: Reconcile the AWS infrastructure
- **WHEN** Git-managed infrastructure changes are applied while AWS workers are running
- **THEN** running workers are not terminated or resized by the infrastructure apply itself

#### Scenario: Inspect repository and pipeline logs
- **WHEN** a user reads committed configurations or routine CI output
- **THEN** Talos cluster secrets, worker bootstrap configuration, AWS credentials, and machine bootstrap configurations are not exposed in plaintext

#### Scenario: Distinct AWS access from CI and autoscaler
- **WHEN** CI manages infrastructure and Karpenter manages workers
- **THEN** CI uses scoped GitHub OIDC, Karpenter uses its own credential and neither uses the HCP token for AWS

#### Scenario: Autoscaler credential used outside its environment
- **WHEN** the prod autoscaler credential targets an unowned subnet or instance
- **THEN** AWS denies the request

#### Scenario: Remove the autoscaler's node configuration
- **WHEN** the autoscaler's node configuration is deleted from a cluster with no AWS workers
- **THEN** the deletion completes without an AWS authorization error and without an operator removing finalizers

#### Scenario: Destroy an environment with running workers
- **WHEN** an environment is destroyed through the provisioning workflow while AWS workers are running
- **THEN** those instances are terminated and their launch templates removed without waiting for their pods to drain, and no EC2 instance for that environment remains after the destroy completes

#### Scenario: Destroy an environment whose cluster is unreachable
- **WHEN** an environment is destroyed while its Kubernetes API or autoscaler is down and AWS workers exist
- **THEN** the destroy still terminates those instances, removes their launch templates, and removes the environment's network infrastructure

#### Scenario: Autoscaler launches during destroy
- **WHEN** the autoscaler attempts to launch an instance after the destroy has begun removing autoscaled instances
- **THEN** AWS denies the launch, and no instance for that environment remains after the destroy completes

### Requirement: Lint PRs and provision from main only
PR validation SHALL inspect roots and charts without secrets or remote state. Dev deployments SHALL run for trusted repository PRs and main; prod and manual deployments SHALL run only from main. Trusted repository PRs SHALL update dev; main SHALL update dev and prod independently after lint succeeds. Fork PRs SHALL validate only. CI SHALL have scoped permission to manage the tagged fixed AWS control plane while Karpenter owns worker launch.

#### Scenario: Independent production deployment
- **WHEN** a production revision is selected
- **THEN** infrastructure and all Argo applications use that same selected revision without requiring a successful dev deployment

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** validation lints the OpenTofu roots and charts without state or secrets, then trusted repository PRs deploy dev; fork PRs stop after validation

#### Scenario: Push to main
- **WHEN** a validated change reaches main
- **THEN** dev and prod receive the selected revision in independent jobs; an absent cluster can bootstrap during apply

#### Scenario: Manual run from another branch
- **WHEN** a manual workflow dispatch targets a ref other than `main`
- **THEN** no infrastructure apply or destroy job runs

#### Scenario: CI credential used to launch or terminate other instances
- **WHEN** CI attempts to launch an instance other than the tagged pinned control plane or terminate unowned compute
- **THEN** AWS denies the request

## REMOVED Requirements

### Requirement: AWS burst capacity is stateless only
**Reason**: Persistent AWS workloads are now supported.
**Migration**: Remove the admission policy, stateless taints and corresponding tolerations; use EBS for persistent AWS claims.

## RENAMED Requirements

- FROM: `### Requirement: Persistent storage remains on fixed Proxmox nodes`
- TO: `### Requirement: Storage follows environment capabilities`
