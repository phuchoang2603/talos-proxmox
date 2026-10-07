## 1. Prerequisites and credentials

- [x] 1.1 Confirm `replace-hyperdx-with-grafana` is merged and archived, `auth.phuchoang.sbs`, `kubeflow.phuchoang.sbs`, and `grafana.phuchoang.sbs` have no existing records in the `phuchoang.sbs` zone, and "Always Use HTTPS" is enabled for the zone; record the check in the PR
- [x] 1.2 In `terraform/foundation/doppler.tf`, add `GRAFANA_OIDC_CLIENT_SECRET` to the prod-only `random_password.observability` set; verify `tofu validate` passes and a plan shows one new password and secret with sensitive values
- [x] 1.3 Apply the foundation root locally; verify `doppler secrets --project talos-proxmox --config prod --only-names` lists `GRAFANA_OIDC_CLIENT_SECRET`

## 2. Dex

- [x] 2.1 In `apps/components/auth/values.yaml`, set `identity.issuer` to `https://auth.phuchoang.sbs/dex` and the Kubeflow redirect to `https://kubeflow.phuchoang.sbs/oauth2/callback`; verify `helm template` renders `dex-config` with the public issuer and only the HTTPS redirect
- [x] 2.2 Add a `grafana` static client to the `dex-config` template with redirect `https://grafana.phuchoang.sbs/login/generic_oauth` and its secret from `GRAFANA_OIDC_CLIENT_SECRET`; verify the rendered template references the remote key and contains no secret value
- [x] 2.3 Add a `TunnelBinding` in `auth` for the `dex` Service with FQDN `auth.phuchoang.sbs`, target `http://dex.auth.svc:5556`, and `tunnelRef` `ClusterTunnel/talos-proxmox`; verify `helm template` renders it with the explicit target
- [x] 2.4 Remove the `/dex/` route from the `auth` `VirtualService` and the `/dex/*` and `/dex/**` exclusions from both `AuthorizationPolicy` resources; verify `helm template` renders only the `/oauth2/` route and exclusions
- [x] 2.5 Extend `templates/validate.yaml` to fail rendering when `identity.issuer` or `identity.redirectURI` is not `https://`; verify `helm template` fails with `--set identity.issuer=http://x` and succeeds with the defaults

## 3. OAuth2 Proxy and Istio

- [x] 3.1 Set OAuth2 Proxy to `oidc-issuer-url: https://auth.phuchoang.sbs/dex`, `skip-oidc-discovery: "true"`, `login-url: https://auth.phuchoang.sbs/dex/auth`, `redeem-url` and `oidc-jwks-url` on `http://dex.auth.svc.cluster.local:5556/dex/{token,keys}`, `redirect-url: https://kubeflow.phuchoang.sbs/oauth2/callback`, `cookie-secure: "true"`, and `cookie-domain: kubeflow.phuchoang.sbs`; verify the rendered Deployment args contain these values and no `localhost`
- [x] 3.2 Set the `RequestAuthentication` `issuer` to the public issuer and `jwksUri` to `http://dex.auth.svc.cluster.local:5556/dex/keys`; verify `helm template` renders both

## 4. Kubeflow publication

- [x] 4.1 Add a `TunnelBinding` in `istio-system` from the `kubeflow` component for `istio-ingressgateway` with FQDN `kubeflow.phuchoang.sbs` and target `http://istio-ingressgateway.istio-system.svc:80`; verify `helm template` renders it in `istio-system` with the explicit target

## 5. Grafana Dex login

- [x] 5.1 Add an ExternalSecret `grafana-oidc` in `observability` from `GRAFANA_OIDC_CLIENT_SECRET` and expose it to Grafana as `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET`; verify the rendered Deployment reads it from the Secret
- [x] 5.2 Configure `grafana.ini`: `server.root_url = https://grafana.phuchoang.sbs`, and `auth.generic_oauth` with name `Dex`, client `grafana`, scopes `openid email profile`, PKCE, `auth_url` public, `token_url` and `api_url` on Dex's in-cluster address, `allow_sign_up = true`, `role_attribute_path` mapping the operator email to `Admin`, and `role_attribute_strict = true`; keep the login form and `users.allow_sign_up = false`; verify the rendered `grafana.ini` contains these settings
- [x] 5.3 Add the operator email as an `observability` value and a lint-workflow check that it equals `apps/components/auth/values.yaml` `identity.email` (a chart cannot read another component's values); verify the check fails when they differ
- [x] 5.4 Add a `TunnelBinding` in `observability` for the Grafana Service with FQDN `grafana.phuchoang.sbs` and an explicit target on port 80; verify `helm template` renders it and the `grafana-ui` LoadBalancer Service is unchanged

## 6. Documentation

- [x] 6.1 Rewrite the access section of `docs/operations/kubeflow.md`: public URL `https://kubeflow.phuchoang.sbs`, Dex login, removal of the port-forward flow, and the internet-exposure warning; verify no `localhost:8080` login instruction remains
- [x] 6.2 Update `docs/operations/cluster-access.md` with the three public URLs, Grafana Dex login, and the LAN admin-password fallback; verify the URLs match the bindings
- [x] 6.3 Update the "Public hostnames" section of `docs/architecture/gitops.md` to list the platform's own three bindings and their owners, alongside application-repository bindings; verify it matches the rendered bindings
- [x] 6.4 Update `docs/reference/secrets.md` with `GRAFANA_OIDC_CLIENT_SECRET`, its consumers (`dex-config`, `grafana-oidc`), and the Dex restart needed after rotation; verify the tables match design.md

## 7. Validation

- [x] 7.1 Run the lint workflow's chart and OpenTofu checks locally in `devenv shell`; verify they pass
- [ ] 7.2 After merge, restart Dex from Argo CD; verify the three `TunnelBinding`s are ready, the CNAME and ownership TXT records exist, and `curl https://auth.phuchoang.sbs/dex/.well-known/openid-configuration` shows only `https://auth.phuchoang.sbs/dex` endpoints
- [ ] 7.3 Verify `curl -I http://kubeflow.phuchoang.sbs` returns an HTTPS redirect, an anonymous `https://kubeflow.phuchoang.sbs` request redirects to Dex, and logging in with `AUTH_DEX_PASSWORD` reaches the Kubeflow Dashboard with secure session cookies
- [ ] 7.4 Verify `https://grafana.phuchoang.sbs` Dex login gives the operator the Admin role, and an authorization request with an unregistered redirect URI is rejected by Dex
- [ ] 7.5 Verify the fallback: at `http://10.69.12.128` the admin password logs in, and with the `talos-proxmox` `cloudflared` Deployment scaled to 0 temporarily, the LAN login still works; restore the replicas and verify the public hostnames recover
- [ ] 7.6 Verify Istio JWT validation uses the in-cluster JWKS: an authenticated Kubeflow request succeeds, and istiod logs show no JWKS fetch from `auth.phuchoang.sbs`
