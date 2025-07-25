# OpenTelemetry Filter Processor Test

This test demonstrates the OpenTelemetry Filter processor configuration for filtering out unwanted telemetry data.

## 🎯 What This Test Does

The test validates that the Filter processor can:
- Filter traces based on span and resource attributes
- Filter metrics based on metric names and resource attributes  
- Filter logs based on log body content
- Only allow "green" telemetry data while filtering out "red" data

## 📋 Test Resources

### 1. OpenTelemetry Collector with Filter Processor
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: filterprocessor
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  config:
    receivers:
      otlp:
        protocols:
          grpc: {}
          http: {}

    exporters:
      debug:
        verbosity: detailed

    processors:
      filter:
        error_mode: ignore
        traces:
          span:
            - 'attributes["traces-env"] == "red"'
            - 'resource.attributes["traces-colour"] == "red"'
        metrics:
          metric:
              - 'name == "gen" and resource.attributes["metrics-colour"] == "red"'
        logs:
          log_record:
            - 'IsMatch(body, "drop message")'

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [filter]
          exporters: [debug]
        metrics:
          receivers: [otlp]
          processors: [filter]
          exporters: [debug]
        logs:
          receivers: [otlp]
          processors: [filter]
          exporters: [debug]
```

### 2. Telemetry Data Generator
The test generates traces, metrics, and logs with various attributes and content to test the filtering capabilities.

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy collector with filter processor
2. **Generate Telemetry Data** - Send traces, metrics, and logs with both "red" and "green" attributes
3. **Wait for Processing** - Allow 5 seconds for telemetry data to be processed
4. **Check Filtered Data** - Verify that only "green" data passes through while "red" data is filtered out

## 🔍 Filter Rules Applied

### Trace Filtering:
- **Filter out**: Spans with `traces-env` attribute equal to "red"
- **Filter out**: Spans with resource attribute `traces-colour` equal to "red"
- **Allow through**: Spans with `traces-colour` equal to "green"

### Metric Filtering:
- **Filter out**: Metrics named "gen" with resource attribute `metrics-colour` equal to "red"
- **Allow through**: Metrics with `metrics-colour` equal to "green"

### Log Filtering:
- **Filter out**: Log records containing "drop message" in the body
- **Allow through**: Other log records

## 🔍 Verification

The test verification script checks for:

**Expected Data (should be present):**
- `logs-colour: Str(green)` - Green logs passed through
- `metrics-colour: Str(green)` - Green metrics passed through  
- `traces-colour: Str(green)` - Green traces passed through

**Filtered Data (should NOT be present):**
- `logs-colour: Str(red)` - Red logs filtered out
- `metrics-colour: Str(red)` - Red metrics filtered out
- `traces-colour: Str(red)` - Red traces filtered out

## 🧹 Cleanup

The test runs in the default namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses `error_mode: ignore` to continue processing even if filter errors occur
- Filters apply to all three telemetry data types: traces, metrics, and logs
- Filter conditions use OTTL (OpenTelemetry Transformation Language) expressions
- Supports complex conditions with logical operators and functions
- Debug exporter allows verification of filtered data output 