# LLM and agent platform

The platform pins KServe presets to v0.21.0, agentgateway to v1.7.0, kagent to 0.10.4, agentregistry to 0.4.0, and Agent Substrate to 0.0.9. Talos remains 1.13.9 and Kubernetes remains 1.36.3. KEDA and Kueue are not installed.

KServe's upstream `kserve-runtime-configs` chart contains the `kserve-config-llm-*` presets; `kserve-llmisvc-resources` contains controller resources. The Kubeflow component installs only the presets in `ml`, without another controller, serving runtimes, or GIE CRDs. agentgateway starts after the existing inference CRDs and supplies GatewayClass `agentgateway`; application charts own Gateways, routes, and policies.

| Consumer contract | Name |
| --- | --- |
| GatewayClass | `agentgateway` |
| Preset namespace | `ml` |
| Registry HTTP API | `http://agentregistry.agentregistry.svc:12121` |
| kagent namespace / UI | `kagent` / `kagent-ui:8080`, ClusterIP |
| WorkerPool | `kagent/kagent-default`, one gVisor worker |
| Worker mesh principal | `cluster.local/ns/kagent/sa/default` |
| Substrate API | `dns:///api.ate-system.svc:443` |
| Substrate snapshots | `s3://platform-dev/substrate/` in dev; `s3://platform-prod-142737101504-us-east-1/substrate/` in prod |

The kagent chart creates its WorkerPool and worker pods in its own namespace. Both `kagent` and `ate-system` allow privileged pods; `kagent` joins Istio ambient so actor traffic carries the worker identity. The app's mesh policy must admit that principal to its gateway. No gateway, model, default ModelConfig, built-in agent, or built-in tool is installed by this platform set. kagent watches `ml` and `kagent`; agentregistry's namespaced RBAC is restricted to `ml`.

kagent and agentregistry each use a single CNPG PostgreSQL instance and a 2 GiB PVC. Substrate uses JWT authentication and the upstream six-member Valkey cluster. Its RustFS deployment is disabled. The snapshot identity can access only `substrate/` in the environment's existing platform bucket. Application SandboxAgents must set their snapshot location under that prefix; the upstream default is a GCS location.

## Credentials

All private credentials live in platform Doppler `dev` / `prod` and reach pods through External Secrets. The public Substrate CA certificate is committed per environment so the upstream CA ConfigMap can be rendered without generating keys during GitOps reconciliation. The TLS server certificate expires after one year; rotate the full credential set and commit the matching public CA before expiry.

Enter the repository's devenv with OpenSSL available, then run:

```sh
python hack/bootstrap-agent-platform-secrets.py --environment dev
python hack/bootstrap-agent-platform-secrets.py --environment prod
```

The helper preserves existing complete credential sets and creates missing database passwords and JWT-mode certificates/signing pools. It never prints values. Foundation includes the database passwords and the prod snapshot IAM identity. Dev's dedicated MinIO policy is `terraform/cluster/env/dev/minio-substrate-policy.json`; provision its identity using the helper's optional `--minio-admin-file` with `minio-client` available. The private file is JSON with `accessKey` and `secretKey` fields. The helper writes the resulting keys to `OBJECT_SUBSTRATE_ACCESS_KEY_ID` and `OBJECT_SUBSTRATE_SECRET_ACCESS_KEY`.

`auth.jwt.issuer` must match the cluster's `/.well-known/openid-configuration` issuer. Check it after rebuilding a cluster, especially when its API address changes. No PodCertificate or ClusterTrustBundle feature gates are enabled.

## Rollout

PR provisioning applies dev. Prod remains manual through **Manual Provision** on main after explicit rollout confirmation. Restricting prod's shared training GPU pool to `g6.xlarge` also restricts Kubeflow training. Installing these controllers does not create an application Gateway or launch a GPU node.
