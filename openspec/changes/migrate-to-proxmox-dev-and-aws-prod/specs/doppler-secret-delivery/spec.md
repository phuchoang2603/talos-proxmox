## MODIFIED Requirements

### Requirement: Doppler as the single secret source
The platform SHALL store generated and operator-issued credentials in the matching dev/prod Doppler config. Foundation SHALL be recreatable without imports of deleted resources and generate application credentials for both environments. Cluster roots SHALL generate only credentials required by their backend. Operator-issued credentials SHALL be restored privately. CI SHALL NOT write secrets through the Doppler CLI.

#### Scenario: Fresh foundation
- **WHEN** foundation is rebuilt from empty state
- **THEN** both configs and scoped tokens are created and no obsolete imports are required

#### Scenario: Cluster apply
- **WHEN** a cluster root is applied
- **THEN** its backend-specific generated credentials reach its Doppler config; only prod receives AWS worker and CSI credentials

#### Scenario: Autoscaler key creation
- **WHEN** prod is applied from fresh state
- **THEN** its autoscaler access key is generated and stored in prod Doppler without manual creation; dev requires no autoscaler key

#### Scenario: Telemetry credential generation
- **WHEN** foundation is applied
- **THEN** both configs contain independently generated Grafana credentials unless dev retains its recovered credential

#### Scenario: Environment rebuild keeps telemetry credentials
- **WHEN** an environment is destroyed and re-provisioned
- **THEN** its telemetry credentials in Doppler are unchanged

#### Scenario: Retired component credentials
- **WHEN** a component that consumed an operator-entered secret is removed from the platform
- **THEN** its keys are deleted from the Doppler configs that held them

#### Scenario: Retired generated credentials
- **WHEN** the foundation root stops generating a telemetry credential and is applied
- **THEN** that key is deleted from the Doppler configs that held it
