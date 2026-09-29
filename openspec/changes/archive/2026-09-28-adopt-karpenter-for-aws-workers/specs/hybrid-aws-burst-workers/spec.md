## MODIFIED Requirements

### Requirement: Bounded, independently autoscaled AWS workers
The platform SHALL provision Talos worker nodes for the dev and prod clusters directly from pending pods, choosing among multiple instance types, availability zones, and both spot and on-demand capacity. Each environment SHALL bound its AWS workers by total CPU and memory limits and SHALL support a zero-worker idle state. The provisioner MUST NOT launch new capacity once the environment's provisioned resources reach those limits. AWS scaling MUST NOT change the fixed Proxmox inventory, and in-cluster scaling control MUST remain available when the AWS worker count is zero. When an AWS instance terminates for any reason, its Node object MUST be removed from the cluster without a separate cleanup job.

#### Scenario: Burst from zero
- **WHEN** an eligible pending workload requires AWS capacity and no AWS worker exists
- **THEN** an AWS worker sized for the pending pods joins the cluster and runs the workload within the configured limits

#### Scenario: Return to zero
- **WHEN** AWS workers are empty, or their pods fit on fewer or cheaper nodes, and the consolidation delay has elapsed
- **THEN** unneeded AWS workers are drained and terminated, and the AWS worker count can return to zero while Proxmox nodes and scaling control remain available

#### Scenario: Reach capacity limit
- **WHEN** eligible pending workloads require more CPU or memory than the environment's remaining limit
- **THEN** no worker is launched past the limit and the excess workloads remain visibly pending

#### Scenario: Spot capacity is reclaimed
- **WHEN** AWS reclaims a spot worker hosting stateless burst pods
- **THEN** the pods are rescheduled onto remaining or newly provisioned capacity, and the lost worker's Node object is removed from the cluster

#### Scenario: Instance is terminated outside the cluster
- **WHEN** an AWS worker instance is terminated from the AWS console or API
- **THEN** its Node object is removed from the cluster without an operator or scheduled job deleting it

### Requirement: Secure, Git-managed reconciliation
The platform SHALL manage Proxmox and AWS infrastructure in one root with a separate HCP Terraform state workspace per cluster environment, and reconcile in-cluster autoscaling, storage drivers, and storage policies declaratively from Git. It MUST protect Talos identities, worker bootstrap configuration, and cloud credentials from repository disclosure, and use different credentials for HCP Terraform state, AWS provisioning, and on-premises autoscaling. The on-premises autoscaler's AWS credential MUST be able to launch, tag, and terminate only instances for its own environment, using only that environment's subnets, security group, worker AMI, and worker instance profile. AWS worker instances MUST NOT receive IAM permissions. Destroying an environment MUST terminate its autoscaled AWS instances and remove the launch templates created for them before its network infrastructure is removed.

#### Scenario: Reconcile the AWS infrastructure
- **WHEN** Git-managed infrastructure changes are applied while AWS workers are running
- **THEN** running workers are not terminated or resized by the infrastructure apply itself

#### Scenario: Inspect repository and pipeline logs
- **WHEN** a user reads committed configurations or routine CI output
- **THEN** Talos cluster secrets, worker bootstrap configuration, AWS credentials, and machine bootstrap configurations are not exposed in plaintext

#### Scenario: Distinct AWS access from CI and autoscaler
- **WHEN** CI plans/provisions AWS infrastructure and the on-premises autoscaler launches or terminates AWS workers
- **THEN** neither process authenticates to AWS with the HCP Terraform token, and the autoscaler cannot use the broader CI provisioning credential

#### Scenario: Autoscaler credential used outside its environment
- **WHEN** one environment's autoscaler credential attempts to launch an instance in the other environment's subnets or terminate the other environment's workers
- **THEN** AWS denies the request

#### Scenario: Destroy an environment with running workers
- **WHEN** an environment is destroyed through the provisioning workflow while AWS workers are running
- **THEN** those instances are terminated and their launch templates removed, and no EC2 instance for that environment remains after the destroy completes

### Requirement: Lint PRs and provision from main only
The platform SHALL lint all OpenTofu roots and platform charts on pull requests targeting `main` without exposing state, AWS credentials, or Doppler environment secrets. Only a push or explicitly dispatched workflow on `main` SHALL plan and apply changes. AWS access in CI MUST use a scoped GitHub OIDC role, separate from the HCP Terraform token; CI MUST NOT launch AWS worker instances itself. The on-premises autoscaler SHALL have separate credentials, limited to managing its environment's workers, before it is enabled.

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** the OpenTofu roots and platform charts are linted without accessing remote state or deployment secrets

#### Scenario: Push to main
- **WHEN** reviewed changes are pushed to `main`
- **THEN** dev and prod generate fresh plans and apply through their main-only deployment environments

#### Scenario: Manual run from another branch
- **WHEN** a manual workflow dispatch targets a ref other than `main`
- **THEN** no infrastructure apply or destroy job runs

## ADDED Requirements

### Requirement: AWS workers follow declared configuration
AWS workers SHALL be launched from the environment's pinned Talos AMI and its current Talos worker configuration. When either changes, existing AWS workers MUST be replaced by workers using the new values, subject to the same disruption rules as consolidation. AWS workers SHALL also be replaced after a declared maximum lifetime.

#### Scenario: Talos version or configuration changes
- **WHEN** an apply changes an environment's worker AMI or Talos worker configuration while AWS workers are running
- **THEN** those workers are drained and replaced by workers running the new AMI and configuration, without an operator draining them by hand

#### Scenario: Worker reaches maximum lifetime
- **WHEN** an AWS worker has run longer than the declared maximum lifetime
- **THEN** it is drained and replaced if its workloads still need AWS capacity, or removed if they do not
