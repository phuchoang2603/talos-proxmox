## 1. Gate and identity foundation

- [ ] 1.1 Gate. Configure the RustFS OpenID provider (`CLAIM_NAME=sub`, audience `sts.rustfs`) against a temporary public issuer for dev, create a policy named `system:serviceaccount:default:sts-probe` for one prefix, and exchange a projected token from that ServiceAccount. Verify that the read and write succeed inside the prefix and are denied outside it. If the mapping fails, stop and report.
- [ ] 1.2 Set the Talos API server `service-account-issuer`/`service-account-jwks-uri` to `https://oidc.<env>.phuchoang.sbs` in `terraform/modules/proxmox/locals.tf`, and add the unauthenticated issuer-discovery `ClusterRoleBinding`. Verify `tofu validate` passes and the render shows both arguments.
- [ ] 1.3 Publish only `/.well-known/openid-configuration` and `/openid/v1/jwks` from the API server at `oidc.dev.phuchoang.sbs` through the cloudflare-tunnel component. Verify the render includes no other path.
- [x] 1.4 Add the tenant inventory `apps/components/tenants/values.yaml` and `apps/components/tenants/platform-object-access.yaml`, using the fields in design D1, for `gateway`, `marketplace` and the platform workloads (Kubeflow pipeline runner, Substrate, Langfuse, Polaris, OpenMetadata). Verify `helm lint` passes.
- [ ] 1.5 Replace `consumer_projects`, `rustfs_consumers`, the RustFS users and service accounts, and the `object_*` Doppler writes in `terraform/foundation` with one `minio_iam_policy` per inventory `objectAccess` entry, named after its `sub`, plus the RustFS OpenID settings. Remove `env/dev/minio-*-policy.json` in both roots. Verify `tofu validate` passes and grep finds no `minio_iam_user`, `minio_iam_service_account` or `OBJECT_.*ACCESS_KEY`.
- [ ] 1.6 Issue Doppler tenant tokens only for inventory entries with `doppler`. Delete `random_password` and `doppler_secret` resources for internal credentials, and any cross-project copy such as `CLICKHOUSE_GRAFANA_PASSWORD` into the gateway. Verify a plan creates no Doppler key outside the externally-originated list in design D3.

## 2. Tenants chart and secret delivery

- [x] 2.1 Create `apps/components/tenants` to render the D6 objects per tenant: Namespaces, Profile, optional Doppler stores with token ExternalSecrets, the D5 platform `kubernetes` stores with reader Roles restricted by `resourceNames`, ResourceQuotas, the AppProject and the root Application. Verify the dev render contains exactly those objects for both tenants.
- [x] 2.2 Register `tenants` in `apps/argocd/platform/values.yaml` after `external-secrets` and `kubeflow`. Verify the platform chart lint and conftest pass.
- [x] 2.3 In `apps/components/external-secrets/values.yaml`, remove `gateway-doppler` and `marketplace-doppler` and exclude tenant-labelled namespaces from the platform store. Reduce `terraform/platform/external-secrets.tf` to the platform token. Verify grep finds no `gateway-doppler`, `marketplace-doppler` or `ESO_.*_DOPPLER_TOKEN` consumer Secret in `kube-system`.
- [ ] 2.4 Add conftest rules that reject: a tenant AppProject whose `clusterResourceWhitelist` is not empty; any rendered Secret or ExternalSecret key matching `ACCESS_KEY|SECRET_ACCESS_KEY`; and any ExternalSecret that reads an internal credential from the platform Doppler store. Verify each rule fails on a fixture and passes on the render.

## 3. Platform components use generated credentials and workload identity

- [ ] 3.1 Convert every platform ExternalSecret that reads an internal credential to CNPG-generated, ESO-generator or cert-manager sources, per design D3, across `auth`, `observability`, `kagent`, `agentregistry`, `substrate`, `openmetadata` and `kubeflow`. Verify that every remaining `remoteRef.key` in the render appears in the D3 external list.
- [ ] 3.2 Move Dex client secrets to generator ExternalSecrets in `auth`, delivered to each client namespace through platform `kubernetes` stores. Verify the render and that oauth2-proxy login works on dev.
- [ ] 3.3 Give Substrate and the Kubeflow pipeline runner projected `sts.rustfs` tokens and web-identity environment variables, with KFP `fromEnv: true`. Remove their object key ExternalSecrets. Verify grep finds no object keys in those components.

## 4. Kubeflow multi-user and shared services

- [ ] 4.1 Re-render vendored Kubeflow from `kubeflow/manifests` `26.10.0` in multi-user mode with upstream namespaces and release tags, keeping the measured memory patches. Verify no workload is in a tenant namespace and no `run-` tag remains.
- [ ] 4.2 Configure profile-controller namespace labels and the `ClusterTrainingRuntime` aggregate role. Delete `profile.yaml`, `training-consumer.yaml`, `training-secret.yaml`, the tenant parts of `pipeline-config.yaml`, and `localModel`. Map the oauth2-proxy identity header. Verify that grepping the render for `gateway`, `fraud` and the owner email finds nothing.
- [ ] 4.3 Add a `langfuse` component with external CNPG, ClickHouse and Redis, web-identity object storage, Dex login, and headless init from a generator Secret that the D5 store exposes to `gateway-llm`. Verify `helm lint` passes.
- [ ] 4.4 Add an `llm-gateway` component: the Gateway with tenant-label `allowedRoutes`, model backends, JWT auth against the cluster JWKS with audience `llm-gateway`, per-`sub` rate limits, and PII and screening policies from `modelClients`. Verify the render has no API key Secret.
- [ ] 4.5 Add a `models` component for the `LLMInferenceService`s and local model cache, and a `polaris` component with web-identity storage and generated tenant principals. Move `openmetadata` to its namespace. Verify each component lints.
- [ ] 4.6 List every object-store client (Spark, Flink, Iceberg REST, ClickHouse S3, KFP, Langfuse, OpenMetadata, Substrate, Polaris) with its web-identity support and pinned version in the change notes. Verify each one supports web identity; if any does not, stop and report.
- [ ] 4.7 Set the Grafana sidecars and vmagent to select all namespaces. Verify the render.

## 5. Docs

- [ ] 5.1 Update `docs/architecture/gitops.md` (ownership, namespaces, tenants) and `docs/reference/secrets.md` (D3 table, workload identity, no object keys). Verify `repo:lint` passes.

## 6. Consumer repositories (separate OpenSpec changes in each repository)

- [ ] 6.1 Gateway: implement design D8. Verify its render contains no cluster-scoped kind, no object key, and no LLM gateway API key.
- [ ] 6.2 Marketplace: implement design D8. Verify its render contains no cluster-scoped kind and no Doppler store reference.

## 7. Rebuild and acceptance

- [ ] 7.1 Delete the internal keys from the Doppler `talos-proxmox` dev config, delete tenant Doppler projects that are no longer declared, and delete the RustFS users. Then destroy and re-provision dev. Verify every Argo CD application is `Synced` and `Healthy`.
- [ ] 7.2 Run every spec scenario on dev and record the evidence, including a rejected cluster-scoped sync, a cross-namespace Secret denial, a scoped STS exchange and an out-of-scope denial, a pipeline run in `gateway-ml`, a model call with a token and one without, and a Langfuse trace. List any scenario not verified.
