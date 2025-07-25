# OpenTelemetry AWS CloudWatch Logs Exporter Test

This test demonstrates the OpenTelemetry AWS CloudWatch Logs and EMF (Embedded Metric Format) exporters for sending logs and metrics to AWS CloudWatch.

## 🎯 What This Test Does

The test validates that the AWS CloudWatch exporters can:
- Export logs to AWS CloudWatch Logs with configurable log groups and streams
- Export metrics to AWS CloudWatch using EMF (Embedded Metric Format)
- Use AWS credentials for authentication and access control
- Process both application logs via sidecar and direct metrics

## 📋 Test Resources

### 1. AWS Credentials Secret
The test creates an AWS credentials secret using the `create-aws-creds-secret.sh` script:
```bash
# Expected environment variables:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
```

### 2. OpenTelemetry Collector with AWS CloudWatch Exporters
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: cwlogs
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
      debug:
        verbosity: detailed
      awsemf:
        log_group_name: ($log_group_name)
        log_stream_name: ($log_stream_name)
        log_retention: 1
        tags: { 'tracing-otel': 'true'}
        namespace: "Tracing-EMF"
        endpoint: "https://logs.us-east-2.amazonaws.com"
        no_verify_ssl: false
        region: "us-east-2"
        max_retries: 1
        dimension_rollup_option: "ZeroAndSingleDimensionRollup"
        resource_to_telemetry_conversion:
          enabled: true
        output_destination: "cloudwatch"
        detailed_metrics: false
        parse_json_encoded_attr_values: []
        metric_declarations: []
        metric_descriptors: []
        retain_initial_value_of_delta_metric: false
      awscloudwatchlogs:
        log_group_name: ($log_group_name)
        log_stream_name: ($log_stream_name)
        raw_log: true
        region: "us-east-2"
        endpoint: "https://logs.us-east-2.amazonaws.com"
        log_retention: 1
        tags: { 'tracing-otel': 'true'}

    processors:
      batch: {}

    service:
      pipelines:
        logs:
          receivers: [otlp]
          processors: [batch]
          exporters: [awscloudwatchlogs]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [awsemf,debug]
```

### 3. RBAC and Namespace Configuration
The test sets up OpenShift-specific RBAC and namespace annotations:
```bash
# Role binding for pod view access
kubectl create rolebinding default-view-$NAMESPACE --role=pod-view --serviceaccount=$NAMESPACE:ta

# Namespace annotations for OpenShift
kubectl annotate namespace ${NAMESPACE} openshift.io/sa.scc.uid-range=1000/1000 --overwrite
kubectl annotate namespace ${NAMESPACE} openshift.io/sa.scc.supplemental-groups=3000/1000 --overwrite
```

### 4. Sidecar Log Collection
The test configures a sidecar OTEL collector to collect application logs and forward them to the main collector.

### 5. Application Log Generator
The test includes an application that generates plaintext logs to be collected and sent to CloudWatch.

### 6. Metrics Generator
The test includes a metrics generator job that sends test metrics for EMF export.

## 🚀 Test Steps

1. **Create AWS Credentials Secret** - Set up AWS authentication using the credential script
2. **Create OTEL Collector** - Deploy main collector with AWS CloudWatch exporters
3. **Create OTEL Sidecar** - Deploy sidecar collector for log collection with namespace RBAC
4. **Create Log Generator App** - Deploy application that generates test logs
5. **Generate Metrics** - Send test metrics to the collector
6. **Check CloudWatch** - Verify logs and metrics are received in AWS CloudWatch

## 🔍 AWS CloudWatch Configuration

### Authentication:
- **Access Method**: AWS Access Key ID and Secret Access Key from Kubernetes secret
- **Region**: `us-east-2`
- **Endpoint**: `https://logs.us-east-2.amazonaws.com`

### CloudWatch Logs Configuration:
- **Log Group**: Dynamic name based on namespace (`tracing-{namespace}`)
- **Log Stream**: Dynamic name (`tracing-{namespace}-stream-emf`)
- **Raw Log**: True (preserve original log format)
- **Log Retention**: 1 day
- **Tags**: `tracing-otel: true`

### EMF (Embedded Metric Format) Configuration:
- **Namespace**: `Tracing-EMF`
- **Dimension Rollup**: `ZeroAndSingleDimensionRollup`
- **Output Destination**: `cloudwatch`
- **Resource to Telemetry Conversion**: Enabled
- **Max Retries**: 1
- **Detailed Metrics**: Disabled

## 🔍 Verification

The test verification script checks that:
- Log groups and streams are created in AWS CloudWatch Logs
- Application logs are successfully exported and visible in CloudWatch
- Metrics are exported in EMF format and visible in CloudWatch Metrics

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses template bindings for dynamic log group and stream names
- Includes both logs and metrics pipelines with different exporters
- Configures OpenShift-specific RBAC and security context constraints
- Uses sidecar pattern for application log collection
- Tests complete pipeline from log generation to AWS CloudWatch storage
- Demonstrates EMF format for CloudWatch metrics with custom namespacing 