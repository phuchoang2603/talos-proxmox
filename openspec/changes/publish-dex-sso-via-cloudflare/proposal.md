## Why

Kubeflow can only be reached through a `kubectl port-forward` to `localhost:8080`, and its auth chart runs an HTTP-only login with insecure cookies that `docs/operations/kubeflow.md` says must never be exposed. Grafana is reachable only on the LAN with a shared admin password. The operator wants both apps usable from anywhere over HTTPS, signed in once through the Dex instance that already serves Kubeflow.

This change depends on `replace-hyperdx-with-grafana` and assumes Grafana runs statelessly in prod's `observability` component at `10.69.12.128`.

## What Changes

- Publish Dex at `https://auth.phuchoang.sbs/dex` through prod's Cloudflare tunnel, and make that URL Dex's issuer.
- **BREAKING:** Publish Kubeflow at `https://kubeflow.phuchoang.sbs` through the same tunnel. OAuth2 Proxy uses the public login and callback URLs with secure cookies. The `localhost:8080` port-forward login stops working.
- Publish Grafana at `https://grafana.phuchoang.sbs` and add Dex as its OIDC login. The Dex identity configured for Kubeflow becomes a Grafana admin, and every other identity is refused. The LAN address and the admin password stay as a fallback login.
- Keep server-side token exchange and signing-key retrieval on Dex's in-cluster address, so token validation does not loop out through the internet.
- Add a `grafana` Dex client whose secret the foundation root generates into Doppler.
- Remove Dex's `/dex/` route from the Kubeflow ingress gateway, since Dex has its own hostname.
- Publish hostnames only through Cloudflare operator `TunnelBinding`s. No router port forwarding and no public IP.

## Capabilities

### New Capabilities

- `public-sso-access`: Dex as the single public identity provider, HTTPS-only publication of Dex, Kubeflow, and Grafana through prod's Cloudflare tunnel, required login and identity-to-role mapping for the published apps, and token validation that does not depend on the public path.

### Modified Capabilities

- `cluster-observability`: the telemetry UI is no longer internal-only. It is also published at a public hostname behind Dex, keeping the LAN address and admin login as a fallback.
- `doppler-secret-delivery`: the foundation root also generates the Grafana single sign-on client secret into the `prod` config.

## Impact

- **Charts:**
  - `apps/components/auth/`: Dex issuer, `grafana` static client, Dex `TunnelBinding`, OAuth2 Proxy URLs and cookie settings, Istio `RequestAuthentication` issuer and JWKS URI, and the removed `/dex/` route.
  - `apps/components/kubeflow/`: a `TunnelBinding` for the Istio ingress gateway in `istio-system`.
  - `apps/components/observability/`: Grafana `generic_oauth` settings, public `root_url`, a client-secret ExternalSecret, and a `TunnelBinding`.
- **OpenTofu:** `terraform/foundation/doppler.tf` adds `GRAFANA_OIDC_CLIENT_SECRET` to prod. An operator applies it locally.
- **Cloudflare:** prod's `prod-talos` tunnel gains three hostnames. The operator creates their CNAME and ownership TXT records in `phuchoang.sbs`.
- **Docs:** `docs/operations/kubeflow.md`, `docs/operations/cluster-access.md`, `docs/architecture/gitops.md`, and `docs/reference/secrets.md`.
- **Security:** the Dex password login and Grafana's admin login become reachable from the internet. Both credentials are random, and Grafana locks out repeated failures. Dex has no lockout.
- **Operations:** Kubeflow and public Grafana depend on Cloudflare. If the tunnel is down, Grafana remains usable on the LAN with the admin password.
