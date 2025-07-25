# OpenTelemetry Forward Connector Test

This test demonstrates the OpenTelemetry Forward connector configuration for aggregating telemetry data from multiple input pipelines into a single output pipeline.

## 🎯 What This Test Does

The test validates that the Forward connector can:
- Collect traces from multiple input pipelines (blue and green)
- Add different attributes to traces in each pipeline
- Forward all traces to a single output pipeline for unified processing
- Maintain trace data integrity through the forwarding process

## 📋 Test Resources

### 1. OpenTelemetry Collector with Forward Connector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otlp-forward-connector
spec:
  mode: deployment
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  config: |
    receivers:
      otlp/blue:
        protocols:
          http:
      otlp/green:
        protocols:
          http:
            endpoint: 0.0.0.0:4319
    processors:
      attributes/blue:
        actions:
        - key: otel_pipeline_tag
          value: "blue"
          action: insert
      attributes/green:
        actions:
        - key: otel_pipeline_tag
          value: "green"
          action: insert
      batch:
    exporters:
      debug:
        verbosity: detailed
    connectors:
      forward:
    service:
      pipelines:
        traces/blue:
          receivers: [otlp/blue]
          processors: [attributes/blue]
          exporters: [forward]
        traces/green:
          receivers: [otlp/green]
          processors: [attributes/green]
          exporters: [forward]
        traces:
          receivers: [forward]
          processors: [batch]
          exporters: [debug]
```

### 2. Trace Generators
The test generates traces with different operation names:
- `lets-go` - Sent to blue pipeline
- `okey-dokey` - Sent to green pipeline

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy collector with forward connector configuration
2. **Generate Traces** - Send traces to both blue and green pipelines
3. **Wait for Processing** - Allow 10 seconds for traces to be processed and forwarded
4. **Check Traces** - Verify traces from both pipelines appear in the output with correct attributes

## 🔍 Forward Connector Architecture

### Input Pipelines:
1. **Blue Pipeline**: `traces/blue`
   - **Receiver**: `otlp/blue` (default HTTP endpoint)
   - **Processor**: `attributes/blue` (adds `otel_pipeline_tag: "blue"`)
   - **Exporter**: `forward` (sends to forward connector)

2. **Green Pipeline**: `traces/green`
   - **Receiver**: `otlp/green` (HTTP endpoint on port 4319)
   - **Processor**: `attributes/green` (adds `otel_pipeline_tag: "green"`)
   - **Exporter**: `forward` (sends to forward connector)

### Output Pipeline:
- **Pipeline**: `traces` (unified output)
- **Receiver**: `forward` (receives from both input pipelines)
- **Processor**: `batch` (batches traces for efficiency)
- **Exporter**: `debug` (outputs traces for verification)

### Data Flow:
```
Blue OTLP → attributes/blue → forward ↘
                                      → unified traces → batch → debug
Green OTLP → attributes/green → forward ↗
```

## 🔍 Verification

The test verification script checks for the presence of:
- `otel_pipeline_tag: Str(blue)` - Confirms blue pipeline processing
- `otel_pipeline_tag: Str(green)` - Confirms green pipeline processing  
- `Name           : lets-go` - Confirms blue trace operation name
- `Name           : okey-dokey` - Confirms green trace operation name

This validates that:
- Both input pipelines are receiving and processing traces
- Attribute processors are adding pipeline-specific tags
- Forward connector is successfully aggregating traces from both pipelines
- All trace data is preserved through the forwarding process

## 🧹 Cleanup

The test runs in the `chainsaw-forwardconnector` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Demonstrates aggregation pattern where multiple input sources feed into a single output
- Each input pipeline can apply different processing before forwarding
- Forward connector acts as a bridge between input and output pipelines
- Enables unified processing and export of traces from multiple sources
- Useful for scenarios requiring trace aggregation from different ingestion points 