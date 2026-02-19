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
├── gcs-secret.yaml                # GCS SA key secret (generated at runtime)
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
- GCS service account key JSON file for uploading scan results to the `secaut-bucket` bucket

### Running outside of Tekton pipelines (CLI)

When running locally or outside the Tekton pipelines, you need to generate the `gcs-secret.yaml` manifest before executing the tests. The Tekton pipelines handle this automatically using the `rapidast-sa-rhosdt-key` Konflux secret.

1. Log in to the target OpenShift cluster:

   ```bash
   oc login --token=<token> --server=<server>
   ```

2. Generate the GCS secret manifest for the component you want to test. This uses `--dry-run=client` to produce the YAML locally; the namespace does not need to exist yet as chainsaw creates it during the test run:

   ```bash
   # For OpenTelemetry
   kubectl create secret generic rapidast-sa-rhosdt-key \
     --from-file=sa-key=/path/to/your/gcs-sa-key.json \
     --namespace=rapidast-otel \
     --dry-run=client -o yaml > tests/e2e-rh-sdl/rapidast-otel/gcs-secret.yaml

   # For Tempo
   kubectl create secret generic rapidast-sa-rhosdt-key \
     --from-file=sa-key=/path/to/your/gcs-sa-key.json \
     --namespace=rapidast-tempo \
     --dry-run=client -o yaml > tests/e2e-rh-sdl/rapidast-tempo/gcs-secret.yaml
   ```

3. Set the `RHOSDT_VERSION` environment variable to tag the scan results in GCS with the product version (e.g., `3.5`, `3.6`):

   ```bash
   export RHOSDT_VERSION=3.5
   ```

4. Run the chainsaw test:

   ```bash
   # Run OpenTelemetry operator security tests
   chainsaw test --config .chainsaw-rh-sdl.yaml --test-dir tests/e2e-rh-sdl/rapidast-otel/

   # Run Tempo operator security tests
   chainsaw test --config .chainsaw-rh-sdl.yaml --test-dir tests/e2e-rh-sdl/rapidast-tempo/
   ```

### Complete SDL Test Suite

```bash
# Generate both secret manifests first (see step 2 above), then set the RHOSDT_VERSION and run all tests
export RHOSDT_VERSION=3.5
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
3. **GCS Secret Creation**: Applies the `rapidast-sa-rhosdt-key` secret for uploading results to Google Cloud Storage
4. **Configuration Generation**: Dynamically creates RapiDAST configuration with authentication tokens and GCS upload settings
5. **Security Scan Execution**: Runs RapiDAST job with ZAP-based security scanning
6. **Result Analysis**: Processes JSON and SARIF reports, evaluating risk levels
7. **Result Upload**: Uploads scan results to the `secaut-bucket` GCS bucket under the `rhosdt/{RHOSDT_VERSION}` directory
8. **Validation**: Asserts successful completion and acceptable security posture

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

## Google Cloud Storage Integration

Scan results are uploaded to GCS for centralized storage and analysis:

```yaml
config:
  googleCloudStorage:
    keyFile: "/etc/gcs/sa-key"
    bucketName: "secaut-bucket"
    directory: "rhosdt/${RHOSDT_VERSION}/otel"  # or "rhosdt/${RHOSDT_VERSION}/tempo"
```

The `RHOSDT_VERSION` environment variable is used to tag results by product version (e.g., `3.5`, `3.6`). It is expanded at runtime by the `create-rapidast-configmap.sh` script.

The GCS service account key is provided via the `rapidast-sa-rhosdt-key` Kubernetes secret (key: `sa-key`), mounted into the RapiDAST job container at `/etc/gcs/sa-key`. In the Tekton pipelines, this secret is sourced from the Konflux secret store. For local CLI runs, the secret manifest must be generated beforehand (see [Running outside of Tekton pipelines](#running-outside-of-tekton-pipelines-cli)).

## Integration with CI/CD

These tests are designed to integrate with CI/CD pipelines as part of the security gates in the development lifecycle. Failed tests indicate potential security vulnerabilities that should be addressed before deployment to production environments.