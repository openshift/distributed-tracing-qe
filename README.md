# Distributed Tracing QE Test Suite

Comprehensive test suite for distributed tracing components, focused on OpenTelemetry (OTel), Jaeger, and Tempo tracing backends. Provides end-to-end testing scenarios, configuration blueprints, and validation scripts for distributed tracing deployments in Kubernetes/OpenShift environments.

## Quick Start

### Prerequisites

- Kubernetes or OpenShift cluster
- [Chainsaw](https://kyverno.github.io/chainsaw/) testing framework
- OpenTelemetry Operator
- `kubectl` or `oc` CLI configured

### Running Tests

```bash
# Run all OpenTelemetry component tests
chainsaw test --test-dir tests/e2e-otel/

# Run specific component test
chainsaw test --test-dir tests/e2e-otel/filelog/

# Run disconnected environment tests
chainsaw test --test-dir tests/e2e-disconnected/

# Run performance/scale tests
chainsaw test --test-dir tests/perfscale-ui-query/

# Run security/SDL tests  
chainsaw test --test-dir tests/e2e-rh-sdl/
```

### Container Build

```bash
# Build test container
docker build -t distributed-tracing-qe .

# Build Konflux variant
docker build -f Dockerfile-konflux -t distributed-tracing-qe-konflux .
```

## Test Categories

### 🔧 OpenTelemetry Components (`tests/e2e-otel/`)

End-to-end tests for individual OpenTelemetry Collector components:

**Receivers**
- `filelog` - File-based log collection
- `hostmetricsreceiver` - Host system metrics
- `k8sclusterreceiver` - Kubernetes cluster metrics
- `k8seventsreceiver` - Kubernetes events
- `kubeletstatsreceiver` - Kubelet statistics
- `k8sobjectsreceiver` - Kubernetes object monitoring
- `journaldreceiver` - systemd journal logs
- `otlpjsonfilereceiver` - OTLP JSON file input

**Processors**
- `transformprocessor` - Data transformation
- `filterprocessor` - Data filtering
- `groupbyattrsprocessor` - Attribute grouping
- `tailsamplingprocessor` - Intelligent sampling
- `probabilisticsamplerprocessor` - Probabilistic sampling

**Exporters**
- `prometheusremotewriteexporter` - Prometheus integration
- `awsxrayexporter` - AWS X-Ray integration
- `awscloudwatchlogsexporter` - AWS CloudWatch logs
- `loadbalancingexporter` - Load balanced export
- `googlemanagedprometheus` - Google Cloud monitoring

**Connectors**
- `routingconnector` - Data routing
- `forwardconnector` - Data forwarding
- `countconnector` - Metric generation

**Extensions**
- `oidcauthextension` - OIDC authentication
- `filestorageext` - File-based storage

### 🔌 Disconnected Environments (`tests/e2e-disconnected/`)

Tests for air-gapped/disconnected environments:
- `compatibility` - Backend compatibility testing
- `jaeger-otel-sidecar` - Jaeger with OTel sidecar
- `monolithic-multitenancy-openshift` - Multi-tenant deployments
- `multitenancy` - Multi-tenant scenarios
- `otlp-metrics-traces` - OTLP metrics and traces
- `smoke-targetallocator` - Target allocator smoke tests

### 🛡️ Security Testing (`tests/e2e-rh-sdl/`)

Red Hat Security Development Lifecycle tests:
- `rapidast-jaeger` - Security testing for Jaeger
- `rapidast-otel` - Security testing for OpenTelemetry
- `rapidast-tempo` - Security testing for Tempo

### 📊 Performance & Scale (`tests/perfscale-*`)

Performance and scalability validation:
- `perfscale-sizing-recommendation` - Sizing recommendations
- `perfscale-ui-query` - UI query performance testing

## Architecture

### Test Structure

Each component test follows this pattern:
```
component-name/
├── README.md                    # Component documentation
├── chainsaw-test.yaml          # Test definition
├── otel-collector.yaml         # OTel Collector configuration
├── *-assert.yaml              # Assertion files for validation
├── check_*.sh                 # Verification scripts
└── additional resources...     # Supporting manifests
```

### Key Technologies

- **Chainsaw** - Test orchestration framework
- **OpenTelemetry Operator** - Manages OTel Collector deployments
- **Tempo** - Distributed tracing backend (Grafana)
- **Jaeger** - Distributed tracing backend (legacy/compatibility)
- **Kubernetes/OpenShift** - Container orchestration platforms

### Test Verification

Tests include shell scripts that:
- Query collector pods for expected log patterns
- Verify trace data in backend systems
- Validate metrics collection and export
- Check component-specific functionality

Scripts use `kubectl` commands with retry logic for eventual consistency.

## Development

### Adding Component Tests

1. Create component directory under appropriate test category
2. Follow established naming patterns
3. Include `chainsaw-test.yaml` with test steps
4. Add verification scripts for validation
5. Document component purpose in `README.md`

### Test Patterns

- Use Chainsaw assert blocks for resource validation
- Implement timeout-based verification for async operations
- Include positive and negative test cases
- Verify component logs for expected behavior

### Container Images

- Tests use specific OTel Collector image versions
- Cloud integrations require credential management
- Test containers include necessary CLI tools

## Configuration Templates

Test directories provide production-ready configuration examples for:
- RBAC setup and permissions
- Resource management and limits
- Data processing pipelines
- Monitoring integration
- Security and authentication

## Use Cases by Category

**Metrics Collection**
- Infrastructure: `hostmetricsreceiver`, `kubeletstatsreceiver`
- Application: `k8sclusterreceiver`, `k8sobjectsreceiver`
- Export: `prometheusremotewriteexporter`, `googlemanagedprometheus`

**Log Management**
- Collection: `filelog`, `journaldreceiver`
- Processing: `transformprocessor`, `filterprocessor`
- Export: `awscloudwatchlogsexporter`

**Distributed Tracing**
- Collection: `otlpjsonfilereceiver`
- Processing: `tailsamplingprocessor`, `groupbyattrsprocessor`
- Export: `awsxrayexporter`, `loadbalancingexporter`

## Contributing

1. Follow established directory structure
2. Include comprehensive documentation
3. Provide example configurations
4. Add verification scripts and assertions
5. Document component-specific considerations

## Resources

- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator)
- [Chainsaw Testing Framework](https://kyverno.github.io/chainsaw/)
- [OpenTelemetry Registry](https://opentelemetry.io/ecosystem/registry/)