## MODIFIED Requirements

### Requirement: Secure, Git-managed reconciliation
The platform SHALL manage Proxmox and AWS infrastructure in one root with a separate HCP Terraform state workspace per cluster environment, and reconcile in-cluster autoscaling, storage drivers, and storage policies declaratively from Git. It MUST protect Talos identities, worker bootstrap configuration, and cloud credentials from repository disclosure, and use different credentials for HCP Terraform state, AWS provisioning, and on-premises autoscaling. The on-premises autoscaler's AWS credential MUST be able to launch, tag, and terminate only instances for its own environment, using only that environment's subnets, security group, worker AMI, and worker instance profile, and MUST allow every read the autoscaler needs to remove its own node configuration. AWS worker instances MUST NOT receive IAM permissions. Destroying an environment MUST terminate its autoscaled AWS instances and remove the launch templates created for them before its network infrastructure and worker instance profile are removed. The infrastructure root SHALL perform this cleanup through the AWS API, without depending on the cluster's Kubernetes API or the autoscaler, and MUST revoke the autoscaler credential's permissions before the cleanup so no replacement instance can launch.

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
The platform SHALL lint all OpenTofu roots and platform charts on pull requests targeting `main` without exposing state, AWS credentials, or Doppler environment secrets. Only a push or explicitly dispatched workflow on `main` SHALL plan and apply changes. AWS access in CI MUST use a scoped GitHub OIDC role, separate from the HCP Terraform token; CI MUST NOT be able to launch AWS worker instances itself. CI MAY terminate autoscaled AWS worker instances and delete their launch templates, limited to resources tagged as autoscaled by this platform, so that a destroy can remove them. The on-premises autoscaler SHALL have separate credentials, limited to managing its environment's workers, before it is enabled.

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** the OpenTofu roots and platform charts are linted without accessing remote state or deployment secrets

#### Scenario: Push to main
- **WHEN** reviewed changes are pushed to `main`
- **THEN** dev and prod generate fresh plans and apply through their main-only deployment environments

#### Scenario: Manual run from another branch
- **WHEN** a manual workflow dispatch targets a ref other than `main`
- **THEN** no infrastructure apply or destroy job runs

#### Scenario: CI credential used to launch or terminate other instances
- **WHEN** the CI provisioning role attempts to launch an EC2 instance, or to terminate an instance that is not tagged as an autoscaled worker of this platform
- **THEN** AWS denies the request
