---
name: Distributed Tracing QE Test Suite
version: 1.0.0
description: Comprehensive test suite for distributed tracing components (OpenTelemetry, Jaeger, Tempo)
framework: Chainsaw
platforms:
  - Kubernetes
  - OpenShift
technologies:
  - OpenTelemetry
  - Jaeger
  - Tempo
  - Chainsaw
---

# Distributed Tracing QE Test Suite

This repository provides AI agents with guidance when working with distributed tracing test automation.

## Overview

This repository contains a comprehensive test suite for distributed tracing components, primarily focused on OpenTelemetry (OTel) and Jaeger/Tempo tracing backends. It provides end-to-end testing scenarios, configuration blueprints, and validation scripts for various distributed tracing deployments in Kubernetes/OpenShift environments.

## Agent Instructions

### Test Execution
All tests in this repository use the Chainsaw testing framework (https://kyverno.github.io/chainsaw/).

**Important**: Always run tests from the repository root directory.

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

## Repository Structure

### Test Directories

The repository is organized into the following test categories:

#### `tests/e2e-otel/`
OpenTelemetry component end-to-end tests.
- Individual receiver, processor, exporter, connector, and extension tests
- Each component has its own directory with test cases and verification scripts
- Uses OpenTelemetry Operator for deployment

#### `tests/e2e-disconnected/`
Disconnected/air-gapped environment tests.
- Tests for scenarios without internet connectivity
- Includes multitenancy, compatibility, and target allocator smoke tests
- Uses Tempo and Jaeger backends

#### `tests/e2e-rh-sdl/`
Red Hat Security Development Lifecycle tests.
- Security-focused test scenarios using RapiDAST
- Tests for OTel and Tempo deployments

#### `tests/perfscale-*/`
Performance and scalability tests.
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

## Technology Stack

| Component | Purpose | Notes |
|-----------|---------|-------|
| **Chainsaw** | Test orchestration framework | All test execution |
| **OpenTelemetry Operator** | Manages OTel Collector deployments | Core infrastructure |
| **Tempo** | Distributed tracing backend | Grafana stack |
| **Jaeger** | Distributed tracing backend | Legacy/compatibility |
| **Kubernetes/OpenShift** | Container orchestration | Target platforms |

## Test Verification Patterns

Most tests include shell scripts (`check_*.sh`) that perform validation:

- **Log Pattern Verification**: Query collector pods for expected log patterns
- **Trace Data Validation**: Verify trace data in backend systems
- **Metrics Collection**: Validate metrics collection and export
- **Component Functionality**: Check component-specific functionality

**Implementation Detail**: Scripts use `kubectl` commands to inspect pod logs and query APIs, with retry logic for eventual consistency.

## Development Guidelines

### Adding New Component Tests

When creating new test components, follow these steps:

1. **Directory Structure**: Create component directory under appropriate test category
2. **File Naming**: Follow the established naming patterns for consistency
3. **Test Definition**: Include `chainsaw-test.yaml` with test steps
4. **Verification Scripts**: Add validation scripts for component functionality
5. **Documentation**: Document component purpose and configuration in `README.md`

### Test Assertion Best Practices

- **Resource Validation**: Use Chainsaw's assert blocks to validate resource creation
- **Async Operations**: Implement timeout-based verification for eventual consistency
- **Coverage**: Include both positive (success) and negative (failure) test cases
- **Logging**: Verify component logs for expected behavior patterns

### Container Image Management

- **Version Pinning**: Tests use specific OTel Collector image versions
- **Credentials**: Cloud provider integrations require credential management
- **Tools**: Test containers include necessary CLI tools (`kubectl`, `oc`, `aws`, etc.)

## Agent Behavior Notes

- **Read Before Modify**: Always read existing test files before making changes
- **Pattern Consistency**: Maintain consistency with existing test patterns
- **Verification**: Run tests after modifications to ensure functionality
- **Documentation**: Update relevant README files when adding new components