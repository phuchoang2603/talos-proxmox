## Context

See proposal.md for motivation. The current state that shapes the approach:

- `apps/components/auth` (prod, `auth` namespace) runs Dex 2.45.1 and OAuth2 Proxy 7.15.5. Dex's config is an ESO-templated Secret, `dex-config`. It has issuer `http://dex.auth.svc.cluster.local:5556/dex`, Kubernetes storage, one static password user (`identity.email`, bcrypt hash from `AUTH_DEX_PASSWORD_BCRYPT`), and one static client, `kubeflow-oidc-authservice`, with redirect `http://localhost:8080/oauth2/callback`.
- OAuth2 Proxy uses `oidc-issuer-url` set to the internal issuer, `login-url: http://localhost:8080/dex/auth`, `redeem-url` set to the internal token endpoint, `cookie-secure: "false"`, and `cookie-samesite: lax`. The browser-facing and server-side Dex URLs are already split.
- The `auth` chart also renders, in `istio-system`:
  - a `VirtualService` on `kubeflow/kubeflow-gateway` routing `/dex/` to Dex and `/oauth2/` to OAuth2 Proxy;
  - a CUSTOM `AuthorizationPolicy` that sends everything except `/dex/*` and `/oauth2/*` to OAuth2 Proxy;
  - a DENY policy for requests without a JWT principal;
  - a `RequestAuthentication` whose issuer is the internal Dex URL. It has no `jwksUri`, so istiod discovers keys from the issuer.
- `istio-ingressgateway` in `istio-system` is a ClusterIP Service with ports 15021, 80, and 443. `kubeflow-gateway` accepts host `*` on port 80. Kubeflow's web apps already set `APP_SECURE_COOKIES=true`.
- The `cloudflare-tunnel` component runs `ClusterTunnel` `talos-proxmox` for the existing `prod-talos` tunnel in zone `phuchoang.sbs`. A `TunnelBinding` lives in its target Service's namespace. Its subject's `target` defaults to the Service's first port, so it is set explicitly here. The operator creates a proxied CNAME and an ownership TXT record for each FQDN. Records survive an environment destroy, and the rebuilt tunnel reclaims them.
- After `replace-hyperdx-with-grafana`, Grafana runs statelessly in `observability` with `root_url` `http://10.69.12.128` and the admin password from `GRAFANA_ADMIN_PASSWORD`.

## Goals / Non-Goals

**Goals:**
- One login, the Dex password user, for Kubeflow and Grafana over HTTPS from anywhere.
- Standard OIDC: Dex's discovery document advertises URLs a browser can use, so future clients such as Argo CD can be added by configuration alone.
- No new inbound path to the LAN besides the existing outbound Cloudflare tunnel.

**Non-Goals:**
- Cloudflare Access, WAF rules, or other zone-level settings managed from this repository.
- Upstream identity connectors such as GitHub or Google, and more Dex users.
- Publishing Argo CD or any dev service.
- Multi-user Kubeflow Profiles or Grafana teams.

## Decisions

### Hostnames and routing

```
 internet ──HTTPS──▶ Cloudflare edge (TLS) ──▶ prod-talos tunnel ──▶ cloudflared (prod)
                                                                     │ plain HTTP, in-cluster
   auth.phuchoang.sbs      ──▶ dex.auth.svc:5556                     ◀┤ TunnelBinding (auth)
   kubeflow.phuchoang.sbs  ──▶ istio-ingressgateway.istio-system:80  ◀┤ TunnelBinding (istio-system)
   grafana.phuchoang.sbs   ──▶ observability-grafana.observability:80◀┘ TunnelBinding (observability)

   LAN only:  http://10.69.12.128 ──▶ Grafana (admin password fallback)
```

Each binding sets an explicit `target`. The ingress gateway's first port is the 15021 status port, and Grafana's Service name follows its release name, which is confirmed when templating. The Dex binding belongs to `auth`, the gateway binding to `kubeflow` (rendered into `istio-system`), and the Grafana binding to `observability`. Each binding has the same owner as the routing it exposes.

Dex gets its own hostname instead of staying under `kubeflow.phuchoang.sbs/dex/`. That way Grafana login does not depend on the Kubeflow ingress gateway, the OAuth2 Proxy authorization policy, or Kubeflow being healthy. The `/dex/` route and its exclusions in the two `AuthorizationPolicy` resources are removed.

### Public issuer, in-cluster back channel

Dex's issuer becomes `https://auth.phuchoang.sbs/dex`, so its discovery document and ID tokens carry the public URL. Every server-side call goes to the in-cluster address, so validation never travels from the cluster out to Cloudflare and back:

| Client | Browser-facing | Server-side (in-cluster `http://dex.auth.svc.cluster.local:5556/dex`) |
|---|---|---|
| OAuth2 Proxy | `login-url` public `/auth` | `skip-oidc-discovery: true`, `redeem-url` `/token`, `oidc-jwks-url` `/keys`; `oidc-issuer-url` public (matched against `iss`) |
| Istio `RequestAuthentication` | — | `issuer` public, `jwksUri` `/keys` |
| Grafana `generic_oauth` | `auth_url` public `/auth` | `token_url` `/token`, `api_url` `/userinfo` |

Alternative considered: keep the internal issuer and only change the browser URLs, as the current port-forward setup does. That needs no Istio or OAuth2 Proxy issuer change. But Dex's discovery document would keep advertising unreachable endpoints, so any client that uses discovery, such as Argo CD's OIDC login, could not be added later.

### Kubeflow over HTTPS

OAuth2 Proxy switches to `redirect-url: https://kubeflow.phuchoang.sbs/oauth2/callback`, `cookie-secure: "true"`, and `cookie-domain` limited to `kubeflow.phuchoang.sbs`. The Kubeflow client's `redirectURIs` changes to the same callback. The `localhost:8080` redirect is dropped: with secure cookies and a public issuer, the port-forward login can no longer finish.

The `auth` chart's `validate.yaml` gains checks that fail rendering if the issuer or redirect is not `https://`. That enforces the documented rule that this HTTP configuration must never be exposed.

### Grafana Dex login

- `server.root_url` becomes `https://grafana.phuchoang.sbs`.
- `auth.generic_oauth` settings:
  - `enabled`, `name = Dex`, `client_id = grafana`;
  - `client_secret` from `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET`, sourced from a new ExternalSecret `grafana-oidc`;
  - `scopes = openid email profile`, `use_pkce = true`;
  - `allow_sign_up = true`, which is required because a stateless Grafana creates the user on each fresh login;
  - `role_attribute_path` maps `identity.email` to `Admin` and everything else to an empty role, with `role_attribute_strict = true`, so any other identity is refused.
- Dex gains a static client `grafana` with redirect `https://grafana.phuchoang.sbs/login/generic_oauth` and the same secret.
- The username/password form stays enabled, and `users.allow_sign_up` stays `false`, so the admin password works on the LAN and the public hostname when Dex or Cloudflare is down.
- `security.cookie_secure` stays `false`. A secure cookie would make the LAN fallback over plain HTTP impossible. The public hostname is HTTPS-only at the edge.

The operator email lives in `apps/components/auth/values.yaml`. Grafana's copy is a value in `observability`, and validation checks that the two match.

### Client secret

`terraform/foundation` adds `GRAFANA_OIDC_CLIENT_SECRET` to the prod-only `random_password.observability` set. `auth`'s `dex-config` template and `observability`'s `grafana-oidc` ExternalSecret both read it. Dex reads its config only at startup, so Dex is restarted from Argo CD after the first sync and after any rotation of this secret. The Kubeflow client secret stays operator-entered (`AUTH_OIDC_CLIENT_SECRET`), unchanged.

Alternative considered: an operator-entered secret, like the existing `AUTH_*` keys. Generation keeps the value out of anyone's hands and follows the telemetry credentials' pattern.

## Risks / Trade-offs

- [The Dex password login is internet-facing, and Dex has no lockout] → The password is random and held only in Doppler. Adding a Cloudflare rate-limit rule on `auth.phuchoang.sbs` in the zone is recommended to the operator but not managed here.
- [The Grafana admin form is internet-facing] → A random 32-character password and Grafana's failed-login lockout. Disabling the form would remove the LAN fallback.
- [Plain HTTP at the edge] → The `phuchoang.sbs` zone must have "Always Use HTTPS" enabled. Validation checks that `http://` requests redirect.
- [Kubeflow is experimental and becomes internet-reachable] → Only the single Dex identity can pass the OAuth2 Proxy and JWT policies. The experimental-status warning in `docs/operations/kubeflow.md` stays.
- [A Cloudflare outage stops all Kubeflow access] → Accepted. Grafana keeps its LAN fallback.
- [Grafana may not validate the ID token's issuer or signature] → Grafana receives the token directly from Dex's token endpoint over the in-cluster connection, in exchange for a one-time code, so no third party can substitute one. Role mapping is strict.
- [The Dex config Secret changes without a Dex restart] → Restart Dex from Argo CD after the first sync and on rotation. Document it in `docs/reference/secrets.md`.
- [Hostname ownership conflicts] → If any of the three names already has a record without the tunnel's ownership TXT, the operator refuses it. Check the zone before merging.

## Migration Plan

1. Merge and archive `replace-hyperdx-with-grafana` first.
2. Confirm the three hostnames are free in `phuchoang.sbs`, and that "Always Use HTTPS" is on.
3. Operator applies `terraform/foundation` locally and confirms that `GRAFANA_OIDC_CLIENT_SECRET` exists in prod.
4. Merge. Prod's Argo CD syncs `auth`, `kubeflow`, and `observability`. Then restart Dex so it loads the new issuer and client.
5. Validate Dex discovery, Kubeflow login, Grafana Dex login, the LAN fallback, and the `http://` redirect.

Rollback: revert the merge and restart Dex. Kubeflow returns to port-forward access. The operator removes the three bindings' DNS records when it deletes the bindings. The foundation key can stay.
