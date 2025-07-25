# OpenTelemetry Count Connector Test

This test demonstrates the OpenTelemetry Count connector configuration for counting telemetry data and exposing the counts as metrics.

## 🎯 What This Test Does

The test validates that the Count connector can:
- Count logs, metrics, and traces by specified attributes
- Generate count metrics for each telemetry type (logs, datapoints, spans)
- Export count metrics to Prometheus for monitoring
- Use OpenShift user workload monitoring for metric verification

## 📋 Test Resources

### 1. User Workload Monitoring Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```

### 2. OpenTelemetry Collector with Count Connector
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: count
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  observability:
    metrics:
      enableMetrics: true
  config:
    receivers:
      otlp:
        protocols:
          grpc: {}
          http:  {}
    processors: {}
    connectors:
      count:
        logs:
          dev.log.count:
            description: The number of logs from each environment.
            attributes:
              - key: telemetrygentype
                default_value: unspecified_environment
        datapoints:
          dev.metrics.datapoint:
            description: The number of metric datapoints from each environment.
            attributes:
              - key: telemetrygentype
                default_value: unspecified_environment
        spans:
          dev.span.count:
            description: The number of spans from each environment.
            attributes:
              - key: telemetrygentype
                default_value: unspecified_environment
    exporters:
      debug: {}
      prometheus:
        endpoint: 0.0.0.0:8889
        resource_to_telemetry_conversion:
          enabled: true # by default resource attributes are dropped
    service:
      pipelines:
        traces:
          receivers: [otlp]
          exporters: [count]
        metrics:
          receivers: [otlp]
          exporters: [count]
        logs:
          receivers: [otlp]
          exporters: [count]
        metrics/count:
          receivers: [count]
          exporters: [prometheus, debug]
```

### 3. Telemetry Data Generator
The test generates logs, metrics, and traces with the `telemetrygentype` attribute to test counting functionality.

## 🚀 Test Steps

1. **Enable User Workload Monitoring** - Configure OpenShift cluster monitoring for user workloads
2. **Create OTEL Collector** - Deploy collector with count connector and Prometheus exporter
3. **Generate Telemetry Data** - Send traces, metrics, and logs to test counting
4. **Verify Metrics** - Check count metrics are exposed and accessible via Thanos querier

## 🔍 Count Connector Configuration

### Counting Rules:
1. **Log Count**: `dev.log.count`
   - Counts log records by `telemetrygentype` attribute
   - Default value: `unspecified_environment`
   - Expected result: `dev_log_count_total{telemetrygentype="logs"}` = 1

2. **Metrics Datapoint Count**: `dev.metrics.datapoint`  
   - Counts metric datapoints by `telemetrygentype` attribute
   - Default value: `unspecified_environment`
   - Expected result: `dev_metrics_datapoint_total{telemetrygentype="metrics"}` = 1

3. **Span Count**: `dev.span.count`
   - Counts trace spans by `telemetrygentype` attribute
   - Default value: `unspecified_environment`
   - Expected result: `dev_span_count_total{telemetrygentype="traces"}` = 10

### Pipeline Architecture:
- **Input Pipelines**: Separate pipelines for traces, metrics, and logs all export to the count connector
- **Count Connector**: Generates count metrics for each telemetry type
- **Output Pipeline**: `metrics/count` receives count metrics and exports to Prometheus

### Export Configuration:
- **Prometheus Endpoint**: `0.0.0.0:8889`
- **Resource to Telemetry Conversion**: Enabled to include resource attributes as labels
- **Debug Exporter**: Provides detailed output for verification

## 🔍 Verification

The test verification script checks specific count metrics using OpenShift's Thanos querier:
- `dev_log_count_total{telemetrygentype="logs"}` = 1
- `dev_metrics_datapoint_total{telemetrygentype="metrics"}` = 1  
- `dev_span_count_total{telemetrygentype="traces"}` = 10
- `metric_count_total{telemetrygentype="metrics"}` = 1

The script uses:
- OpenShift user workload monitoring token for authentication
- Thanos querier API endpoint for metric queries
- Polling mechanism to wait for expected metric values

## 🧹 Cleanup

The test runs in the default namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses count connector to transform telemetry data into count metrics
- Demonstrates attribute-based counting with configurable grouping keys
- Integrates with OpenShift user workload monitoring for verification
- Supports counting across all three telemetry data types simultaneously
- Provides default values for missing attributes in counting logic
- Exports count metrics in Prometheus format for external monitoring systems 