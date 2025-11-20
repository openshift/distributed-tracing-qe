# Red Hat Secure Development Lifecycle (SDL) Tests

This test suite provides Dynamic Application Security Testing (DAST) capabilities for distributed tracing components using RapiDAST, a Red Hat security testing framework. The tests perform automated security scans on Kubernetes operator APIs for OpenTelemetry, Jaeger, and Tempo deployments.

## Overview

The e2e-rh-sdl test suite implements security testing as part of the Red Hat Secure Development Lifecycle (SDL) process. It uses [RapiDAST](https://github.com/RedHatProductSecurity/rapidast) to perform dynamic security analysis on operator API endpoints, helping identify potential security vulnerabilities in distributed tracing operator deployments.

## Test Components

The test suite contains two main test scenarios:

### 1. rapidast-otel/
Security testing for OpenTelemetry operator APIs
- **Target**: OpenTelemetry operator API endpoints (`opentelemetry.io/v1alpha1`)
- **Scope**: Kubernetes API server endpoints for OTel resources

### 2. rapidast-tempo/
Security testing for Tempo operator APIs
- **Target**: Tempo operator API endpoints (`tempo.grafana.com/v1alpha1`)
- **Scope**: Kubernetes API server endpoints for Tempo resources

## Test Architecture

Each test scenario follows the same pattern:

```
rapidast-{component}/
├── chainsaw-test.yaml              # Chainsaw test definition
├── create-project.yaml             # Namespace creation
├── assert-create-project.yaml      # Project creation validation
├── create-sa.yaml                  # Service account with privileged access
├── assert-create-sa.yaml          # Service account validation
├── create-rapidast-configmap.sh   # Dynamic config generation script
├── assert-rapidast-configmap.yaml # ConfigMap validation
├── rapidast-job.yaml              # RapiDAST security scan job
└── assert-rapidast-job.yaml       # Job execution validation
```

## Security Scan Configuration

### Authentication
- Uses Kubernetes service account tokens for API authentication
- Creates privileged service accounts with cluster-level access
- Dynamically generates bearer tokens for each test run

### Scan Targets
- **API Endpoints**: Kubernetes API server OpenAPI v3 endpoints
- **Authentication**: Bearer token-based authentication
- **Scope**: Operator-specific API groups and versions

### Scan Policy
- **Active Scan**: Uses "Operator-scan" policy for targeted testing
- **Passive Scan**: Enabled with minimal disabled rules
- **API Scan**: Focuses on OpenAPI v3 endpoint discovery and testing

### Result Filtering
The tests include intelligent filtering to reduce false positives:

```yaml
exclusions:
  enabled: True
  rules:
    - name: "Filter unauthorized responses on operator APIs"
      description: "Exclude 401 unauthorized responses which are expected for operator API endpoints"
      cel_expression: '.result.webResponse.statusCode == 401'
    - name: "Filter forbidden responses on operator APIs"
      description: "Exclude 403 forbidden responses which are expected for operator API endpoints"
      cel_expression: '.result.webResponse.statusCode == 403'
    - name: "Filter operator API discovery false positives"
      description: "Exclude common false positives from operator API discovery scans"
      cel_expression: '.result.ruleId in ["10015", "10027", "10096", "10024", "10054"]'
```

## Running the Tests

### Prerequisites
- OpenShift/Kubernetes cluster with appropriate permissions
- Chainsaw testing framework installed
- Target operators (OpenTelemetry or Tempo) deployed

### Individual Test Execution

```bash
# Run OpenTelemetry operator security tests
chainsaw test --config .chainsaw-rh-sdl.yaml --test-dir tests/e2e-rh-sdl/rapidast-otel/

# Run Tempo operator security tests
chainsaw test --config .chainsaw-rh-sdl.yaml --test-dir tests/e2e-rh-sdl/rapidast-tempo/
```

### Complete SDL Test Suite

```bash
# Run all Red Hat Secure Development Lifecycle tests
chainsaw test --config .chainsaw-rh-sdl.yaml --test-dir tests/e2e-rh-sdl/
```

### Configuration

The tests use a dedicated Chainsaw configuration file (`.chainsaw-rh-sdl.yaml`) that provides:
- **Extended Timeouts**: 30-minute assert timeout to accommodate lengthy security scans
- **Parallel Execution**: Up to 4 parallel test executions
- **Optimized Cleanup**: 5-minute timeouts for resource cleanup operations

## Test Execution Flow

1. **Project Setup**: Creates dedicated namespace for Red Hat Secure Development Lifecycle testing
2. **Service Account Creation**: Establishes privileged service account with cluster access
3. **Configuration Generation**: Dynamically creates RapiDAST configuration with authentication tokens
4. **Security Scan Execution**: Runs RapiDAST job with ZAP-based security scanning
5. **Result Analysis**: Processes JSON and SARIF reports, evaluating risk levels
6. **Validation**: Asserts successful completion and acceptable security posture

## Security Scan Results

### Risk Assessment
- **High Risk**: Security issues that require immediate attention (fails test)
- **Medium Risk**: Security concerns that should be reviewed (logged but passing)
- **Low/Info**: Informational findings (filtered out)

### Report Formats
- **JSON Report**: ZAP native format with detailed vulnerability information
- **SARIF Report**: Static Analysis Results Interchange Format for tooling integration

### Success Criteria
Tests pass when:
- RapiDAST job completes successfully
- No high-risk security vulnerabilities are detected
- Configuration and authentication work correctly
- API endpoints are properly discovered and tested

## Resource Requirements

### Compute Resources
- **CPU**: 500m requests, 2000m limits
- **Memory**: 1Gi requests, 4Gi limits
- **Storage**: 1Gi PersistentVolume for results

### Security Context
- **Privileged**: Required for comprehensive security testing
- **Capabilities**: SYS_ADMIN for advanced scanning features

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   - Verify service account has correct cluster permissions
   - Check token generation in configmap creation scripts

2. **API Discovery Issues**
   - Ensure target operators are properly deployed
   - Verify OpenAPI v3 endpoints are accessible

3. **Resource Constraints**
   - Increase memory limits if scans fail due to OOM
   - Adjust storage if result processing fails

4. **High Risk Findings**
   - Review ZAP reports in job logs
   - Check if findings are legitimate security issues
   - Update exclusion rules if false positives are identified

## Integration with CI/CD

These tests are designed to integrate with CI/CD pipelines as part of the security gates in the development lifecycle. Failed tests indicate potential security vulnerabilities that should be addressed before deployment to production environments.