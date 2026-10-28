## Why

The repository currently defines two Proxmox clusters and treats AWS as stateless burst capacity. Development should instead use the existing Proxmox hardware, while a small, independent Talos production cluster runs entirely in AWS with reusable deployment logic and explicit operating costs.

## What Changes

- **BREAKING**: Replace Proxmox production with one On-Demand `m6a.large` control-plane/workload node and two `m6a.xlarge` Spot workers in one AWS availability zone. Use Karpenter as the single CPU/GPU worker provisioner, preserve x86 images and make worker replacement declarative.
- Rebuild persistent Proxmox dev with one control-plane/workload VM on `pve` and workers on `pve2` and `pve3`, retaining the former production CPU/RAM and local GPU allocation. Minimize application activity, not VM capacity.
- Extract shared Talos identity, configuration, bootstrap and client-output logic; retain provider-specific machine and network modules and one owner per resource.
- **BREAKING**: Remove stateless admission restrictions, the stateless scheduling taint and corresponding tolerations. Support normal persistent workloads on AWS workers using EBS CSI.
- Keep CNPG clusters single-instance. Use local-path in dev and encrypted `gp3` in prod; accept recovery downtime and do not describe the system as highly available.
- Use existing MinIO in dev and generic, private S3 object storage in prod, with purpose-scoped access and retention. Reuse a common Iceberg REST catalog deployment backed by PostgreSQL; evaluate and pin a compatible catalog before rollout.
- Enable the same applicable platform services in both clusters, parameterizing environment identity, storage, domains and object-store endpoints. Use minimal dev replicas and on-demand batch/GPU activity.
- Restore Knative Serving, Eventing and Istio integration before Kubeflow in both environments, including serverless inference and scale-to-zero validation.
- Rework CI promotion, secrets, management access and teardown for the new provider boundary. Recreate the previously destroyed foundation before provisioning; do not attempt another data migration.

## Capabilities

### New Capabilities

- `iceberg-catalog`: Independent per-environment REST catalogs using MinIO or S3, durable catalog state and verified multi-engine commits.

### Modified Capabilities

- `hybrid-aws-burst-workers`: Provider-specific clusters, unrestricted persistent workers, bounded Spot capacity and scoped lifecycle ownership.
- `declarative-platform-bootstrap`: Shared platform, deliberate promotion, provider-specific storage and cloud-resource teardown.
- `doppler-secret-delivery`: Bootstrap from empty foundation and environment-appropriate generated credentials.
- `cluster-observability`: Independent telemetry in both clusters with portable placement and storage.
- `ml-object-staging`: General-purpose prod S3, existing dev MinIO and purpose-scoped consumers.
- `distributed-gpu-training`: Local GPU availability only in dev and optional, explicitly activated cloud training.
- `istio-ambient-ingress`: ClusterIP UIs, Cloudflare access and no LAN LoadBalancer configuration.
- `public-sso-access`: Independent environment hostnames and in-cluster identity validation.

## Impact

Changes affect `terraform/{foundation,cluster,proxmox,aws,platform}`, shared Talos modules, `apps/argocd`, affected component charts, CI and the minimal documented deployment/operations sections. Existing specs explicitly requiring Proxmox prod, stateless AWS workers, no EBS, prod-only services and automatic prod deployment must be superseded. AWS spend, Spot interruptions and the single control plane/database remain deliberate constraints.
