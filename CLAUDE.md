# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains a comprehensive test suite for distributed tracing components, primarily focused on OpenTelemetry (OTel) and Jaeger/Tempo tracing backends. It provides end-to-end testing scenarios, configuration blueprints, and validation scripts for various distributed tracing deployments in Kubernetes/OpenShift environments.

## Key Commands

### Running Tests
All tests use the Chainsaw testing framework (https://kyverno.github.io/chainsaw/):

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

## Architecture Overview

### Test Categories

1. **e2e-otel/**: OpenTelemetry component end-to-end tests
   - Individual receiver, processor, exporter, connector, and extension tests
   - Each component has its own directory with test cases and verification scripts
   - Uses OpenTelemetry Operator for deployment

2. **e2e-disconnected/**: Disconnected/air-gapped environment tests
   - Tests for scenarios without internet connectivity
   - Includes multitenancy, compatibility, and target allocator smoke tests
   - Uses Tempo and Jaeger backends

3. **e2e-rh-sdl/**: Red Hat Security Development Lifecycle tests
   - Security-focused test scenarios using RapiDAST
   - Tests for Jaeger, OTel, and Tempo deployments

4. **perfscale-***: Performance and scalability tests
   - Sizing recommendations and UI query performance tests
   - Load testing and resource usage validation

### Component Test Structure

Each OpenTelemetry component test follows this pattern:
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

- **Chainsaw**: Test orchestration framework
- **OpenTelemetry Operator**: Manages OTel Collector deployments
- **Tempo**: Distributed tracing backend (Grafana)
- **Jaeger**: Distributed tracing backend (legacy/compatibility)
- **Kubernetes/OpenShift**: Container orchestration platforms

### Test Verification

Most tests include shell scripts (check_*.sh) that:
- Query collector pods for expected log patterns
- Verify trace data in backend systems
- Validate metrics collection and export
- Check component-specific functionality

The scripts typically use `kubectl` commands to inspect pod logs and query APIs, with retry logic for eventual consistency.

## Development Patterns

### Adding New Component Tests
1. Create component directory under appropriate test category
2. Follow the established naming pattern for files
3. Include chainsaw-test.yaml with test steps
4. Add verification scripts for component validation
5. Document component purpose and configuration in README.md

### Test Assertion Patterns
- Use Chainsaw's assert blocks to validate resource creation
- Implement timeout-based verification for async operations
- Include both positive (success) and negative (failure) test cases
- Verify component logs for expected behavior patterns

### Container Image Management
- Tests use specific OTel Collector image versions
- Cloud provider integrations require credential management
- Test containers include necessary CLI tools (kubectl, oc, aws, etc.)