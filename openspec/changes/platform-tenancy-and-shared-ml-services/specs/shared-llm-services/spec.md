## Purpose

Provide one platform-run instance each of LLM observability, the model gateway and shared model serving, which tenants consume through their own identities instead of installing their own.

## ADDED Requirements

### Requirement: Platform-run LLM observability
The platform SHALL run one Langfuse instance in each environment, with durable state in platform-owned Postgres, ClickHouse, Redis and its own object-store identity. Langfuse SHALL use platform SSO for interactive access. For each tenant that enables it, the platform SHALL create a Langfuse project and API keys in the cluster and deliver them to the tenant through cross-namespace credential delivery.

#### Scenario: Tenant traces reach Langfuse
- **WHEN** a gateway workload sends traces using its delivered keys
- **THEN** the traces appear in the gateway project, and other tenants' keys cannot read them

#### Scenario: Restart preserves traces
- **WHEN** Langfuse workloads restart
- **THEN** previously ingested traces and prompts remain available

### Requirement: Platform-run model gateway
The platform SHALL run one model gateway in the `llm-gateway` namespace. It SHALL expose an OpenAI-compatible in-cluster endpoint for every shared model, with per-client rate limits, PII masking and request screening. The gateway SHALL authenticate a client by verifying a projected ServiceAccount token with the model-gateway audience against the cluster issuer. It SHALL authorize the client against the tenant inventory's list of model-gateway clients, expressed as namespace and ServiceAccount. No model-gateway API key SHALL exist.

#### Scenario: Tenant client calls a model
- **WHEN** a listed tenant ServiceAccount calls the gateway with its projected token
- **THEN** the request is screened, rate-limited per client, and served by the named shared model

#### Scenario: Unlisted or missing identity
- **WHEN** a request carries no token, a token with another audience, or a token for an unlisted ServiceAccount
- **THEN** the gateway rejects it without forwarding it to a model

### Requirement: Shared model serving
The platform SHALL serve shared LLMs in the `models` namespace from a platform-owned model list, and SHALL keep a local model cache for the models it serves. Tenants SHALL NOT run their own copies of shared models.

#### Scenario: Model list change
- **WHEN** a model is added to the platform model list and reconciled
- **THEN** it is cached, served, and reachable through the model gateway under its listed name

### Requirement: Tenant-owned agents
Tenants SHALL own their agents, tools, retrieval services and prompts as namespaced resources in their own namespaces, and SHALL consume shared LLM services only through their identities, delivered credentials and in-cluster endpoints.

#### Scenario: Agent namespace isolation
- **WHEN** gateway agents run in `gateway-llm`
- **THEN** they call models through the model gateway with their ServiceAccount tokens and trace to Langfuse, and every resource they need is in `gateway-llm` or is a platform endpoint
