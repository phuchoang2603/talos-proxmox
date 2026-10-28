## Context

See `proposal.md` for motivation and scope. `terraform/cluster` unconditionally calls the Proxmox module, which owns the Talos identity and cluster endpoint, and passes its outputs into the AWS burst module. `terraform/platform` assumes every environment needs Karpenter. The shared Argo chart enables most application services only in prod; storage, object endpoints, hostnames and telemetry placement embed the current Proxmox production identity.

The earlier teardown completed successfully, including foundation and all five HCP workspaces. There is no state migration or application-data copy to perform. Operator-issued credentials and old prod application values were recovered privately from the encrypted CLI cache. Foundation has restored appropriate external credentials and dev application values; prod application credentials are generated independently. Public Cloudflare tunnels and the existing MinIO installation were external prerequisites, not provisioned by these Terraform roots.

The accepted production baseline is one On-Demand `m6a.xlarge` running control plane and workloads, plus one `m6a.xlarge` On-Demand worker with optional Spot burst capacity. Both nodes have 4 vCPUs/16 GiB, for 8 vCPUs/32 GiB total before system reservations. Initial networking uses one AZ. This is a cost-conscious, non-HA cluster; neither a second control plane nor replicated PostgreSQL is implied.

## Goals / Non-Goals

**Goals:**

- Share Talos configuration, charts, application ownership and deployment interfaces while keeping each cluster operationally independent.
- Preserve the former Proxmox production VM CPU/RAM allocations: `pve` 8 cores/32 GiB, `pve2` 8 cores/16 GiB, `pve3` 4 cores/16 GiB. Use one control-plane/workload VM on `pve`, workers on the other hosts, and retain the GPU on `pve`.
- Bound steady-state compute, storage, optional GPU capacity and background jobs. Make interruption, recovery and deletion behavior explicit and testable.

**Non-Goals:**

- HA control planes, synchronous replicated databases, multi-AZ storage failover, or preserving previously discarded data.
- Replacing existing dev MinIO, introducing dev S3 buckets, or copying prod data into dev.
- An unrestricted instance-type allowlist, automatic On-Demand worker fallback, or automatically enabling expensive GPU workloads.

## Decisions

### 1. Preserve layered roots and separate reusable Talos behavior from machines

Keep `foundation`, per-environment `cluster`, per-environment `platform` and in-cluster Argo CD. Platform installs Talos CCM before Argo CD to initialize the AWS control plane; GitOps installs Argo CD OAuth secrets/tunnel access after ESO and Cloudflare CRDs. Extract environment-local Talos machine secrets and common CNI/proxy/KubePrism, kubelet reservations and scheduling configuration out of `terraform/proxmox`. Keep platform-specific install disks, network configuration, machine allocation and GPU image details in the respective backend. Bootstrap and client outputs consume a small, consistent endpoint/control-plane inventory interface.

Separate entrypoints at `terraform/cluster/dev` and `terraform/cluster/prod` select Proxmox and AWS respectively, sharing the Talos and generated-secret modules. An inactive provider must not require credentials or try to read the other provider's files. Avoid empty-map placeholder credentials and hardcoded dev-only patches. Move AWS-specific roots behind an explicit module boundary if provider initialization otherwise requires inactive Proxmox authentication.

Alternatives: cloning the Proxmox bootstrap into a second AWS implementation duplicates identity/configuration logic; one giant conditional module obscures provider boundaries and makes dependencies harder to validate.

### 2. One stable AWS control plane and one Karpenter worker provisioner

The AWS backend owns a VPC, one public subnet/AZ, internet gateway, routes, free S3 gateway endpoint, security groups, one On-Demand EC2 instance and stable Elastic IP. Terraform owns this fixed control-plane/workload node; Karpenter is the sole provisioner for both CPU and optional GPU workers. Pin `m6a.xlarge`, amd64 Talos AMIs and versions. Permit changing instance types through validated inputs; do not silently widen the accepted baseline. Keep the control plane's EBS root persistent across instance replacement with an explicit recovery procedure; an EIP alone does not preserve etcd state. Intentional full destroy can remove that disk under the environment's deletion policy.

Run one Karpenter controller on the On-Demand control-plane/workload node so it can replace workers when neither baseline worker is available. Reuse the existing CPU/GPU `EC2NodeClass` construction, pinned image pipeline, provider-ID initialization and `karpenter.sh/unregistered` startup contract after removing all stateless markers. Keep the optional, separately bounded GPU NodePool disabled by default and idle at zero when enabled without demand. Dev does not create AWS worker networking or autoscaler credentials by default.

The pinned Karpenter 1.15.1 chart includes `NodePool.spec.replicas`, and its bundled values mark `staticCapacity` alpha and disabled by default. Enable `settings.featureGates.staticCapacity` explicitly and use a CPU NodePool with `replicas: 1`, `m6a.xlarge`, On-Demand capacity and the selected AZ. Use `limits.nodes: 2` to bound temporary replacement overlap to one extra CPU worker; normal desired capacity remains one. Do not render CPU/memory limits, weight or dynamic consolidation fields for this static pool. Add a demand-driven `aws-cpu-burst` Spot CPU pool under the same controller, sharing the `aws-cpu` EC2NodeClass with the `aws-workers` static baseline. Limit the burst pool to 4 vCPUs/16 GiB (one m6a.xlarge) and consolidate idle/underutilized capacity after five minutes. Preserve dynamic GPU pool configuration under the same controller. Validate these contracts against the pinned CRDs and live Spot replacement before declaring the baseline ready.

Configure an environment-owned SQS queue and EventBridge rules for Karpenter's supported interruption events, wire `settings.interruptionQueue`, and grant scoped event-delivery and controller-consumption permissions. Reuse the same interruption path for CPU and GPU pools. Forceful reclaim can still interrupt workloads. Karpenter retries Spot capacity; the CPU baseline is On-Demand and extra demand-driven CPU capacity is Spot-only. Include drift replacement, the bounded temporary third worker, interruptions and capacity-unavailable cases in validation rather than treating desired capacity as guaranteed readiness. The static-capacity feature's alpha status is an explicit design trade-off to retain one worker provisioner, not a reason to introduce a second one implicitly.

### 3. Affordable networking with explicit management access

Avoid NAT gateways and API load balancers for this single-control-plane design. Public-subnet nodes use public IPv4 for outbound connectivity; this cost is additional to EC2 prices. The control-plane Elastic IP provides a stable TLS endpoint. Use intra-VPC node/pod connectivity and a consistent Cilium configuration; KubeSpan is not a dependency on Proxmox. Do not carry a hybrid-only MTU assumption into the cloud without measuring it.

Restrict Talos and Kubernetes management APIs to explicit operator/CI egress CIDRs and required intra-cluster traffic. CI discovers its public egress address for the AWS apply and passes a temporary `/32` management allowance through the normal input/plan path; stable operator CIDRs remain configured. Do not expose management APIs to `0.0.0.0/0`. Existing Tailscale access remains the documented Proxmox management route. A private AWS routing alternative can be added later if its fixed cost is accepted.

Cloudflare publishes application UIs using ClusterIP Services and existing environment-specific tunnels. Neither environment provisions Cilium LAN IPAM, address pools, L2 announcements or UI LoadBalancer Services. AWS does not render LAN address pools or request unbacked Kubernetes LoadBalancer Services. Port-forward remains available for management when Cloudflare is unavailable.

### 4. Ordinary persistent workloads, EBS in prod and local-path in dev

Delete `burst-stateless-only`, its binding, chart values and tests; remove the `burst.talos.dev/stateless` taint and tolerations from CPU/GPU machine configuration, NodePools and consumers. Preserve only necessary startup and GPU-allocation taints. Do not replace the policy with an environment exception or infer storage eligibility from EC2 node-name prefixes.

Use a common application storage interface. Dev's sole default StorageClass is local-path, with provisioning limited to its fixed nodes. Prod's sole default is encrypted EBS `gp3` through a pinned CSI chart, `WaitForFirstConsumer` and expansion enabled. Prefer ext4 for the initial Talos mount compatibility validation. Give the CSI controller dedicated scoped AWS access; do not grant broad EBS permissions to every workload's node role. Initially reuse the ESO/Doppler credential-delivery pattern; do not make an unimplemented self-hosted OIDC issuer a hidden bootstrap dependency.

Keep all CNPG `instances: 1`, including any catalog database. EBS volumes can reattach to replacement workers in the same AZ, after detachment/fencing. An AZ outage and the single database remain accepted downtime. Snapshots and application-aware backups are recovery tools, not automatic failover. EFS is excluded initially: add Regional EFS only when a concrete workload requires shared POSIX files and its performance/cost is justified. Distributed storage such as Ceph or Longhorn adds unnecessary operating overhead here.

### 5. Shared application membership and lean dev activity

Enable the same applicable platform services in dev/prod through the existing shared Argo component table. Hardware-dependent GPU components and provider-dependent networking/storage remain capability selections. Keep CNPG and application services at one replica initially, and jobs, notebooks and GPU training idle until requested. Avoid daily or continuous batch workloads merely to demonstrate deployment parity.

Use the same purpose-based namespaces in both environments: `data` for Iceberg, OpenMetadata, StarRocks and Spark/Flink jobs; `ml` for Kubeflow, KServe, trainers and ML workloads; `operators` for shared controllers, Argo Workflows and storage provisioners. Retain upstream `knative-serving`, `knative-eventing` and `istio-system` namespaces because their configuration objects and references are namespace-specific. Retain `auth`, `argo-cd`, `observability` and Kubernetes system namespaces. Do not create a `payment-gateway` namespace or watch it; downstream applications create Spark/Flink jobs in platform-owned `data`. Parameterize telemetry labels, PVC storage classes, domains, OAuth issuer/callback values and object endpoints instead of replacing text across vendored manifests at deployment time. Replace `prod-server1`/`prod-server2` selectors with provider-neutral scheduling needs. Remove production defaults pointing at `minio.home.phuchoang.sbs`. Use prod's current public names and dev-specific `<service>-dev.phuchoang.sbs` names such as `auth-dev.phuchoang.sbs`; each cluster owns its own Dex and callbacks. Budget actual rendered requests and runtime memory against the accepted 32 GiB allocation.

Enable the existing pinned Knative Serving and Eventing manifests and cluster-local Istio gateway in both environments before Kubeflow. Retain net-istio, configure KServe for serverless inference, and verify a service becomes Ready, receives traffic and scales to zero after inactivity. Controllers remain available while no inference or event workload is active.

### 6. Generic object storage and a common Iceberg catalog

Provision one private, encrypted, versioned production object bucket named `platform-prod-<account>-<region>`, with separate prefixes for `lakehouse/`, `datasets/`, `artifacts/`, `runs/` and `backups/`. Scope permissions and lifecycle by purpose: run expiration must not delete live table files, checkpoints or backups. Place reusable Talos image-import assets in a distinct foundation-owned bucket, created only when the optional GPU-image pipeline needs it. Replace ML-only names in Terraform and secret contracts; explicitly update every `ML_BUCKET` consumer rather than keeping indefinite aliases.

Dev uses its existing MinIO endpoint with a dev warehouse and scoped credentials; it creates no dev S3 bucket. Both environments expose the same non-secret object-store contract and the same Iceberg REST catalog interface. Table data, manifests and metadata JSON remain in the environment's object storage, while durable catalog registrations/commit coordination live in the catalog's PostgreSQL database.

Select Apache Polaris with relational PostgreSQL persistence as the initial catalog candidate, with a pinned release/chart chosen by a compatibility acceptance test against the repository's Spark, Flink and StarRocks versions. Require authenticated REST access and scoped storage credentials. Do not deploy the Iceberg REST test fixture or an in-memory production catalog. The existing dev MinIO `/iceberg` endpoint is not assumed to be a generic S3 feature; use the common catalog deployment to avoid depending on a MinIO edition-specific API. AWS Glue is an alternative if shared catalog operation is later rejected, but would reduce parity.

### 7. Recreate foundation and change promotion deliberately

Remove unconditional import blocks for the deleted Doppler project/environments. Bootstrap the foundation backend from existing operator HCP authentication, create both configs/tokens/workspaces and GitHub environments declaratively, and generate environment-specific application credentials where the repository owns them. Operator-issued Proxmox, MinIO, Cloudflare, HCP and Tailscale inputs must be entered privately into the new appropriate configs. No secret values enter Git or routine logs.

CI must be allowed to create/manage only the tagged fixed AWS control plane and worker prerequisites; its current ban on `RunInstances` must change for the fixed control plane while Karpenter retains worker launch ownership. Add scoped instance-profile, EIP, Spot prerequisites, SQS/EventBridge interruption infrastructure and storage-cleanup permissions without adopting an administrator role. Preserve distinct CI, autoscaler, CSI, object-consumer and secret-store identities. Dev must not require unused AWS credentials; prod must not require Proxmox/MinIO credentials.

Trusted repository PRs validate and deploy dev; fork PRs validate only. Main validates, deploys dev and deploys prod only after dev succeeds. Manual production deployments remain main-only and require a revision previously deployed successfully to dev. Pin the root and child Argo Applications to the same selected revision so Argo cannot bypass promotion by following main independently. Handle an intentionally absent dev cluster without implicitly recreating it. Deployment environments allow main and trusted PR merge refs for dev, but only main for prod.

### 8. Retained data and complete cloud teardown have separate ownership

Foundation owns account identity, generic object storage and image assets. Cluster owns the fixed EC2 control plane, networking, interruption queue/rules, worker prerequisites and generated machine credentials. Platform owns Karpenter's controller, CPU/GPU NodePools and EC2NodeClasses, as well as the other bootstrap components; Karpenter creates and manages worker instances and launch templates. Argo owns application resources and CSI installation under a single defined owner. Volume provisioners create external resources, so add a cluster-owned cleanup contract for tagged, environment-specific EBS volumes/snapshots and any external controller resources.

Normal environment destroy retains declared persistent data unless an explicit purge is selected. Both paths revoke Karpenter's scale-out permissions, terminate its CPU/GPU workers and remove their launch templates through the cluster-owned AWS sweep, preserve or delete data according to that policy, remove the fixed EC2 control plane and network resources, then reset platform state. Remove interruption rules and the queue through their infrastructure owner. Offline-API cleanup must query AWS ownership tags, not depend on Karpenter or CSI finalizers. A failed cleanup does not empty state or claim a clean environment. Foundation destroy and purge remain explicit operations, performed after environment teardown and followed by deletion of an empty foundation workspace if requested. Retention must not silently prevent the declared environment/network destroy from completing.

## Risks / Trade-offs

- [Single control plane] -> Reserve system CPU/RAM, keep a stable endpoint, document etcd backup/restore and distinguish instance replacement from a clean bootstrap. API downtime is expected during failure or maintenance.
- [Spot eviction or no capacity in the selected AZ] -> Retry replacement, expose pending/unavailable state, checkpoint jobs, bound interruption drain and use same-AZ EBS. Maintain the On-Demand baseline independently of Spot availability.
- [Karpenter static capacity is alpha in the pinned chart] -> Enable it explicitly, pin controller/CRDs together and verify one-worker maintenance, drift and interruption recovery. If acceptance fails, report the limitation before changing the one-provisioner design or worker-count contract.
- [Platform memory is insufficient for the full stack] -> Measure rendered requests plus system overhead and validate real startup; use idle batch components and explicit limits. Report an unmet budget instead of hiding missing services.
- [Single CNPG instance] -> Take application-aware backups and test restoration; acknowledge database downtime even if its EBS data survives.
- [New CSI/catalog compatibility] -> Pin versions and require PVC replacement plus cross-engine Iceberg commit/read tests before declaring readiness. Context7 was attempted but is currently quota-limited; verify current official upstream docs during implementation.
- [Deleted configuration secrets] -> Require private restoration of operator-issued inputs before authenticated plans; do not reuse obsolete deleted keys or invent placeholders.
- [External MinIO or Cloudflare outage] -> Keep environments independent and management port-forward available; object-store or public-UI outages remain visible dependencies within the affected environment.

## Migration Plan

1. Implement and statically validate the shared Talos boundaries, provider configuration, platform values, ownership and revised workflows against empty state.
2. Recreate foundation and restore required operator-issued configuration privately. Review the authenticated plan, including the complete cost inventory, before provisioning.
3. Build dev from the former production hardware allocation using fresh Talos identities and dev namespaces, warehouses and domains. Validate the minimal complete deployment and MinIO-backed Iceberg path.
4. Provision AWS prod's On-Demand control plane and one On-Demand worker, then bootstrap networking, storage and shared platform. Run actual node/pod/storage checks after Terraform installation succeeds.
5. Validate Spot termination/replacement with an EBS-backed workload, CNPG restore, catalog restart and cross-engine reads; verify no production data/service path reaches dev or the home MinIO endpoint.
6. Rehearse retained-data destroy and explicit purge, including cleanup while Kubernetes is unavailable. Capture outcomes before enabling the production promotion path.

Rollback before workload writes is a scoped destroy and rebuild from the last working revision. After writes begin, rollback must use compatible application/catalog versions or restore declared backups; neither changing an AMI nor reverting DNS is a data rollback. Do not restore the discarded Proxmox production topology as an implicit fallback.

## Open Questions

- Exact pinned Polaris and CSI chart releases will be selected using the compatibility acceptance criteria above; do not use floating tags.
- Final PVC sizes, retention quotas and optional image-pipeline activation will follow the measured platform budget. The accepted EC2 shape does not change automatically.
- Stable operator management CIDRs and restored secret values are deployment inputs, not decisions to leave to code defaults.
