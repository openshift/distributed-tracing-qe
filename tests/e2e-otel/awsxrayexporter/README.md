# OpenTelemetry AWS X-Ray Exporter Test

This test demonstrates the OpenTelemetry AWS X-Ray exporter configuration for sending traces to AWS X-Ray service.

## 🎯 What This Test Does

The test validates that the AWS X-Ray exporter can:
- Export traces to AWS X-Ray using AWS credentials
- Configure worker processes and retry settings for reliable delivery
- Include telemetry metadata and AWS log group associations
- Process traces from HotROD application and telemetry generators

## 📋 Test Resources

### 1. AWS Credentials Secret
The test creates an AWS credentials secret using the `create-aws-creds-secret.sh` script:
```bash
# Expected environment variables:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
```

### 2. OpenTelemetry Collector with AWS X-Ray Exporter
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: xray
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  env:
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: aws-credentials
          key: access_key_id
    - name: AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: aws-credentials
          key: secret_access_key
  config:
    receivers:
      otlp:
        protocols:
          grpc: {}
          http: {}

    exporters:
      awsxray:
        num_workers: 2
        endpoint: "https://xray.us-east-2.amazonaws.com"
        request_timeout_seconds: 30
        max_retries: 2
        no_verify_ssl: false
        region: "us-east-2"
        local_mode: false
        index_all_attributes: false
        aws_log_groups: [ikanse=tracing-test]
        telemetry:
          enabled: true
          include_metadata: true
          hostname: "ocp-otel-collector"
          instance_id: "otel-collector-xray"

    processors: {}

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: []
          exporters: [awsxray]
```

### 3. HotROD Application
The test deploys the HotROD (Rides on Demand) demo application to generate realistic traces for X-Ray export.

### 4. Trace Generator
The test includes a trace generator job that sends additional test traces to the collector.

## 🚀 Test Steps

1. **Create AWS Credentials Secret** - Set up AWS authentication using the credential script
2. **Create OTEL Collector** - Deploy collector with AWS X-Ray exporter
3. **Install HotROD App** - Deploy the rides-on-demand demo application  
4. **Generate Traces** - Create traces using the trace generator
5. **Check AWS X-Ray** - Verify traces are received in AWS CloudWatch X-Ray

## 🔍 AWS X-Ray Configuration

### Authentication:
- **Access Method**: AWS Access Key ID and Secret Access Key from Kubernetes secret
- **Region**: `us-east-2`
- **Endpoint**: `https://xray.us-east-2.amazonaws.com`

### Performance Settings:
- **Number of Workers**: 2 parallel workers for trace export
- **Request Timeout**: 30 seconds per request
- **Max Retries**: 2 retry attempts on failure
- **SSL Verification**: Enabled (`no_verify_ssl: false`)

### X-Ray Specific Settings:
- **Local Mode**: Disabled (sends directly to AWS X-Ray service)
- **Index All Attributes**: Disabled (selective attribute indexing)
- **AWS Log Groups**: Associated with `ikanse=tracing-test` log group

### Telemetry Configuration:
- **Telemetry Enabled**: True
- **Include Metadata**: True
- **Hostname**: `ocp-otel-collector`
- **Instance ID**: `otel-collector-xray`

## 🔍 Verification

The test verification script checks that traces are successfully received in AWS CloudWatch X-Ray console and can be queried and visualized.

## 🧹 Cleanup

The test runs in the default namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses AWS credentials from Kubernetes secret for authentication
- Configured for us-east-2 region with specific X-Ray endpoint
- Includes performance tuning with multiple workers and retry logic
- Associates traces with specific AWS log groups for correlation
- Enables telemetry reporting with collector identification
- Tests complete pipeline from OTLP ingestion to AWS X-Ray storage 