## Purpose

Let the operator reach Kubeflow and Grafana on prod from anywhere over HTTPS with one login, using Dex as the single identity provider and prod's Cloudflare tunnel as the only public path.

## ADDED Requirements

### Requirement: Single public identity provider
Prod SHALL run one OIDC identity provider, Dex, reachable at `https://auth.phuchoang.sbs/dex`, and that URL SHALL be its issuer. Its discovery document MUST advertise only browser-reachable HTTPS endpoints. It SHALL authenticate only the identities in its own password store, whose credentials come from the Doppler secret store, and SHALL issue tokens only to the registered Kubeflow and Grafana clients.

#### Scenario: Discovery
- **WHEN** a client fetches `https://auth.phuchoang.sbs/dex/.well-known/openid-configuration`
- **THEN** the issuer and every advertised endpoint start with `https://auth.phuchoang.sbs/dex`

#### Scenario: Operator signs in
- **WHEN** the operator enters the Dex password from Doppler on the Dex login page
- **THEN** Dex completes the login and redirects back to the requesting app

#### Scenario: Unregistered client
- **WHEN** an authorization request names a client ID or redirect URI that is not registered
- **THEN** Dex rejects the request without showing a login form

### Requirement: Publication only through the Cloudflare tunnel
Dex, Kubeflow, and Grafana SHALL be published at `auth.phuchoang.sbs`, `kubeflow.phuchoang.sbs`, and `grafana.phuchoang.sbs` only through prod's Cloudflare tunnel, with DNS records created declaratively from the cluster. They MUST be served only over HTTPS to clients. The platform MUST NOT open router port forwards or assign public IP addresses for them. Dev MUST NOT publish these hostnames.

#### Scenario: HTTPS request
- **WHEN** a client on the internet requests one of the three hostnames over HTTPS
- **THEN** the request reaches the corresponding prod service through the tunnel

#### Scenario: Plain HTTP request
- **WHEN** a client requests one of the three hostnames over plain HTTP
- **THEN** it is redirected to HTTPS before reaching the cluster

#### Scenario: Prod is rebuilt
- **WHEN** prod is destroyed and re-provisioned
- **THEN** the three hostnames resolve to the rebuilt tunnel again without manual DNS changes

### Requirement: Login required for published apps
Every request to Kubeflow's public hostname, except the login callback, SHALL require a Dex session, and Kubeflow's session cookies MUST be marked secure. Grafana's public hostname SHALL require either a Dex login or the Grafana admin password. Neither app MAY allow anonymous access.

#### Scenario: Anonymous Kubeflow request
- **WHEN** a visitor without a session opens `https://kubeflow.phuchoang.sbs`
- **THEN** they are redirected to the Dex login page and no Kubeflow content is returned

#### Scenario: Grafana via Dex
- **WHEN** the operator chooses the Dex option on Grafana's login page and signs in
- **THEN** Grafana opens with the operator logged in

### Requirement: Identity-to-role mapping
Only the operator identity configured for Kubeflow SHALL be granted access through Dex. In Grafana that identity SHALL receive the Admin role, and any other identity that Dex authenticates MUST be refused.

#### Scenario: Operator in Grafana
- **WHEN** the configured operator identity logs in to Grafana through Dex
- **THEN** the session has the Grafana Admin role

#### Scenario: Other identity
- **WHEN** a Dex identity other than the configured operator tries to log in to Grafana
- **THEN** Grafana refuses the login and creates no user

### Requirement: Token validation independent of the public path
Apps and gateways in prod SHALL exchange authorization codes and fetch Dex's signing keys through Dex's in-cluster address, not through the public hostname. A Cloudflare outage MUST NOT prevent Grafana's LAN login with the admin password.

#### Scenario: Cloudflare is unreachable
- **WHEN** the tunnel or Cloudflare's edge is unavailable
- **THEN** the public hostnames fail, and an operator on the LAN can still log in to Grafana at its internal address with the admin password

#### Scenario: Token check inside the cluster
- **WHEN** the Kubeflow gateway validates a Dex token
- **THEN** it uses signing keys fetched from Dex's in-cluster address
