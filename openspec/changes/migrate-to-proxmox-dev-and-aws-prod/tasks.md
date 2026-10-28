## 1. Cluster backends

- [x] 1.1 Extract shared Talos configuration/identity/bootstrap and make provider selection independent; verify both backend plans do not request inactive credentials.
- [x] 1.2 Rebuild dev inventory with the former production CPU/RAM, one control plane and two workers; verify rendered inventory and Talos roles.
- [ ] 1.3 Provision the single-AZ AWS On-Demand m6a.large control plane, stable endpoint and restricted management access; verify an authenticated plan and API readiness.
- [ ] 1.4 Configure Karpenter as sole worker provisioner with two Spot m6a.xlarge nodes, bounded replacement, optional disabled GPU and interruption handling; verify rendered pinned CRDs and live worker replacement.
- [x] 1.5 Remove stateless admission policy, machine taints and consumer tolerations; verify no restriction remains in rendered resources.

## 2. Foundation and storage

- [x] 2.1 Make foundation recreatable from empty state, generate both environments' application credentials and scope cloud identities; verify foundation validation and authenticated plan.
- [ ] 2.2 Replace ML-only S3 naming/contracts with generic purpose-scoped production storage and optional separate image assets; verify consumers and IAM scopes.
- [ ] 2.3 Install pinned EBS CSI with encrypted expandable gp3 in prod, local-path only in dev, and single-instance CNPG throughout; verify default classes and same-AZ volume recovery.
- [ ] 2.4 Implement retained-data/purge cleanup without Kubernetes API dependency; verify offline cleanup and failed-cleanup state preservation.

## 3. Shared applications

- [ ] 3.1 Enable Knative Serving, Eventing, Istio networking and Kubeflow in both environments; verify Helm renders and live serverless inference readiness, requests and scale-to-zero.
- [ ] 3.2 Enable matching application membership and parameterize identity, namespace, object endpoints, storage and domain values; verify both renders and absence of prod-to-dev paths.
- [ ] 3.3 Use minimal application replicas and idle jobs without reducing dev VM capacity; verify rendered resource requests and runtime fit in the accepted AWS allocation.
- [ ] 3.4 Pin and deploy an authenticated PostgreSQL-backed Iceberg REST catalog for MinIO/S3; verify catalog restart and Spark/Flink/StarRocks read/commit compatibility.

## 4. Promotion and rollout

- [ ] 4.1 Update CI for dev deployment, explicit production promotion and consistent Argo revision pinning; verify workflow guards and chart renders.
- [x] 4.2 Restore recovered prod application/external secrets into dev, share appropriate operator credentials and generate independent prod application secrets; verify a secret-only foundation apply, matching restored values and absence of deleted-resource keys.
- [x] 4.6 Complete the remaining foundation resources and verify workspace, IAM, storage and GitHub environment ownership before cluster rollout.
- [ ] 4.3 Apply and validate dev with MinIO, Knative and the local GPU; record node, application and storage readiness.
- [ ] 4.4 Apply and validate prod, Spot replacement, EBS recovery and CNPG restoration; record actual costs, capacity and acceptance results.
- [ ] 4.5 Update only affected operational documentation and run OpenSpec, OpenTofu and Helm validation; record results and remaining limitations.
