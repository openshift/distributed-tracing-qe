# OpenTelemetry Transform Processor Test

This test demonstrates the OpenTelemetry Transform processor configuration for modifying telemetry data attributes and content.

## 🎯 What This Test Does

The test validates that the Transform processor can:
- Modify resource attributes using keep_keys, set, limit, and truncate_all operations
- Transform span attributes and names based on conditions
- Forward transformed traces to Tempo for verification

## 📋 Test Resources

### 1. Tempo Monolithic Instance
```yaml
apiVersion: tempo.grafana.com/v1alpha1
kind: TempoMonolithic
metadata:
  name: tprocssr
spec:
  jaegerui:
    enabled: true
  multitenancy:
    enabled: false
```

### 2. OpenTelemetry Collector with Transform Processor
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: tprocssr
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  config:
    receivers:
      otlp:
        protocols:
          grpc: {}

    exporters:
      otlp:
        endpoint: tempo-tprocssr.chainsaw-tprocssr.svc:4317
        tls:
          insecure: true

    processors:
      transform:
        error_mode: ignore
        trace_statements:
          - context: resource
            statements:
              - keep_keys(attributes, ["service.name", "X-Tenant", "otel.library.name"])
              - set(attributes["X-Tenant"], "blue") where attributes["X-Tenant"] == "green"
              - limit(attributes, 100, [])
              - truncate_all(attributes, 4096)
          - context: span
            statements:
              - set(attributes["net.peer.ip"], "5.6.7.8") where attributes["net.sock.peer.addr"] == "1.2.3.4"
              - set(attributes["peer.service"], "modified-server") where attributes["peer.service"] == "telemetrygen-server"
              - set(attributes["peer.service"], "modified-client") where attributes["peer.service"] == "telemetrygen-client"
              - set(name, "modified-operation") where name == "okey-dokey-0"
              - limit(attributes, 100, [])
              - truncate_all(attributes, 4096)

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [transform]
          exporters: [otlp]
```

### 3. Trace Generator Job
The test uses a telemetrygen job to generate traces with specific attributes that will be transformed by the processor.

### 4. Trace Verification Job
The test verifies that traces are successfully transformed and stored in Tempo by querying the Jaeger API.

## 🚀 Test Steps

1. **Create Tempo Instance** - Deploy Tempo monolithic instance for trace storage
2. **Check Tempo Status** - Verify Tempo instance is ready
3. **Create OTEL Collector** - Deploy collector with transform processor
4. **Generate Traces** - Send traces with specific attributes to be transformed
5. **Verify Traces** - Check that transformed traces are received in Tempo

## 🔍 Transform Rules Applied

### Resource Context Transformations:
- **keep_keys**: Retains only `service.name`, `X-Tenant`, and `otel.library.name` attributes
- **set**: Changes `X-Tenant` from "green" to "blue"
- **limit**: Limits attributes to 100 maximum
- **truncate_all**: Truncates all attribute values to 4096 characters

### Span Context Transformations:
- **IP Address**: Changes `net.sock.peer.addr` "1.2.3.4" to `net.peer.ip` "5.6.7.8"
- **Service Names**: 
  - "telemetrygen-server" → "modified-server"
  - "telemetrygen-client" → "modified-client"
- **Operation Name**: "okey-dokey-0" → "modified-operation"
- **limit**: Limits span attributes to 100 maximum
- **truncate_all**: Truncates all span attribute values to 4096 characters

## 🧹 Cleanup

The test runs in the `chainsaw-tprocssr` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses `error_mode: ignore` to continue processing even if transformation errors occur
- Applies transformations at both resource and span contexts
- Uses conditional statements with `where` clauses for targeted transformations
- Demonstrates attribute filtering, modification, limiting, and truncation
- Integrates with Tempo for end-to-end trace verification 