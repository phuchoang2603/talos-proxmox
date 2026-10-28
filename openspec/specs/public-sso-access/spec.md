# public-sso-access Specification

## Purpose

Let the operator reach Kubeflow and Grafana on prod from anywhere over HTTPS with one login, using Dex as the single identity provider and prod's Cloudflare tunnel as the only public path.

## Requirements

### Requirement: Single public identity provider
Each environment SHALL run independent Dex with environment-specific HTTPS issuer, registered callbacks and private password-store credentials. Discovery SHALL advertise browser-reachable endpoints. Unregistered clients SHALL be rejected.

#### Scenario: Dev login
- **WHEN** a dev client requests discovery
- **THEN** issuer and callbacks use dev hostnames

#### Scenario: Discovery
- **WHEN** a client fetches discovery from either environment
- **THEN** the issuer and advertised endpoints use that environment public HTTPS Dex hostname

#### Scenario: Operator signs in
- **WHEN** the operator enters the Dex password from Doppler on the Dex login page
- **THEN** Dex completes the login and redirects back to the requesting app

#### Scenario: Unregistered client
- **WHEN** an authorization request names a client ID or redirect URI that is not registered
- **THEN** Dex rejects the request without showing a login form

### Requirement: Publication only through the Cloudflare tunnel
Each environment SHALL publish its own auth, Kubeflow and Grafana HTTPS hostnames through its own Cloudflare tunnel with declarative DNS. Dev SHALL NOT claim prod hostnames. No router forwards or direct public app IPs SHALL be required.

#### Scenario: Both clusters publish
- **WHEN** their routes converge
- **THEN** hostnames resolve to the corresponding environment

#### Scenario: HTTPS request
- **WHEN** an internet client requests an environment application hostname over HTTPS
- **THEN** the matching environment tunnel routes to that environment service

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
Apps and gateways SHALL exchange codes and signing keys through their own in-cluster Dex address. Cloudflare outage SHALL preserve admin login through management port-forward.

#### Scenario: Public path fails
- **WHEN** Cloudflare is unavailable
- **THEN** internal signing-key retrieval and management admin login continue

#### Scenario: Cloudflare is unreachable
- **WHEN** Cloudflare or the tunnel fails
- **THEN** public access fails but management port-forward supports Grafana admin login

#### Scenario: Token check inside the cluster
- **WHEN** the Kubeflow gateway validates a Dex token
- **THEN** it uses signing keys fetched from Dex's in-cluster address
