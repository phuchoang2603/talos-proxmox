## Purpose

Run Kubeflow as a shared multi-user platform service whose tenants get ML namespaces as Kubeflow Profiles, with platform-owned training runtimes and no tenant-specific objects in the platform chart.

## ADDED Requirements

### Requirement: Kubeflow in platform namespaces
Kubeflow control-plane components SHALL run only in platform namespaces: `kubeflow` for the pipelines, notebooks, Katib, Trainer, the dashboard and the model registry and catalog, and `kserve` for the KServe controller. No Kubeflow control-plane workload SHALL run in a tenant namespace.

#### Scenario: Control plane placement
- **WHEN** Kubeflow is synced
- **THEN** every Kubeflow controller, API server and web app pod is in `kubeflow` or `kserve`

### Requirement: Tenant ML namespaces are Profiles
Each tenant ML namespace SHALL be a Kubeflow Profile declared in the tenant inventory, owned by the tenant's listed user. Pipelines, notebooks, experiments, training jobs and inference services SHALL run in that Profile namespace and SHALL be isolated per Profile. The per-namespace pipeline launcher and artifact configuration SHALL come from Kubeflow's own profile mechanism. Pipeline artifact access SHALL use the Profile's pipeline-runner ServiceAccount object identity, scoped to the tenant's artifact prefix, with no artifact access key.

#### Scenario: Tenant runs a pipeline
- **WHEN** the gateway owner submits a pipeline in `gateway-ml`
- **THEN** it runs in `gateway-ml`, writes artifacts under the gateway's object prefix, and is not visible from another Profile

#### Scenario: Platform chart is tenant-agnostic
- **WHEN** the platform Kubeflow application is rendered
- **THEN** it contains no tenant service account, tenant namespace, tenant secret or tenant owner email

### Requirement: Shared training runtimes
The platform SHALL publish its GPU training runtimes as cluster-wide runtimes. Every Profile namespace SHALL be able to read and reference them without a tenant-specific binding.

#### Scenario: Tenant references a runtime
- **WHEN** a tenant `TrainJob` in its Profile namespace references a platform GPU runtime
- **THEN** the job is admitted and scheduled under the GPU contract with no per-tenant RBAC object in the platform chart
