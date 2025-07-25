# OpenTelemetry Routing Connector Test

This test demonstrates the OpenTelemetry Routing connector configuration for conditionally routing telemetry data to different pipelines and backends.

## 🎯 What This Test Does

The test validates that the Routing connector can:
- Route traces to different Tempo instances based on tenant attributes
- Use conditional statements to determine routing destinations
- Support default routing for traces that don't match specific conditions
- Forward traces to red, blue, or green Tempo instances based on X-Tenant attribute

## 📋 Test Resources

### 1. Multiple Tempo Instances
The test deploys three separate Tempo monolithic instances:
- `red` - for traces with X-Tenant=red
- `blue` - for traces with X-Tenant=blue  
- `green` - for traces with no matching tenant (default)

### 2. OpenTelemetry Collector with Routing Connector
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: routing
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  config:
    receivers:
      otlp:
        protocols:
          grpc: {}

    exporters:
      otlp/red:
        endpoint: tempo-red.chainsaw-routecnctr.svc:4317
        tls:
          insecure: true
      otlp/green:
        endpoint: tempo-green.chainsaw-routecnctr.svc:4317
        tls:
          insecure: true
      otlp/blue:
        endpoint: tempo-blue.chainsaw-routecnctr.svc:4317
        tls:
          insecure: true

    processors:

    connectors:
      routing:
        error_mode: ignore
        default_pipelines: [traces/green]
        table:
          - statement: route() where attributes["X-Tenant"] == "red"
            pipelines: [traces/red]
          - statement: route() where attributes["X-Tenant"] == "blue"
            pipelines: [traces/blue]

    service:
      pipelines:
        traces/in:
          receivers: [otlp]
          processors: []
          exporters: [routing]
        traces/red:
          receivers: [routing]
          processors: []
          exporters: [otlp/red]
        traces/blue:
          receivers: [routing]
          processors: []
          exporters: [otlp/blue]
        traces/green:
          receivers: [routing]
          processors: []
          exporters: [otlp/green]
```

### 3. Trace Generators
The test generates traces with different tenant attributes to test the routing logic.

## 🚀 Test Steps

1. **Create Tempo Instances** - Deploy three Tempo monolithic instances (red, blue, green)
2. **Check Tempo Status** - Verify all three Tempo instances are ready
3. **Create OTEL Collector** - Deploy collector with routing connector
4. **Generate Traces** - Send traces with different X-Tenant attributes
5. **Verify Traces** - Check that traces are routed to the correct Tempo instances

## 🔍 Routing Logic

### Routing Rules:
1. **Red Route**: `route() where attributes["X-Tenant"] == "red"`
   - Routes to `traces/red` pipeline → `tempo-red` instance
   
2. **Blue Route**: `route() where attributes["X-Tenant"] == "blue"`
   - Routes to `traces/blue` pipeline → `tempo-blue` instance

3. **Default Route**: `default_pipelines: [traces/green]`
   - Routes traces without matching X-Tenant to `tempo-green` instance

### Pipeline Architecture:
- **Input Pipeline**: `traces/in` - Receives all traces via OTLP
- **Routing Connector**: Routes traces based on X-Tenant attribute
- **Output Pipelines**: 
  - `traces/red` - Sends to red Tempo instance
  - `traces/blue` - Sends to blue Tempo instance  
  - `traces/green` - Sends to green Tempo instance (default)

### Error Handling:
- **Error Mode**: `ignore` - Continue processing even if routing errors occur
- **Fallback**: Default pipeline handles traces that don't match any routing rules

## 🔍 Verification

The test verification confirms that:
- Traces with `X-Tenant=red` are stored in the red Tempo instance
- Traces with `X-Tenant=blue` are stored in the blue Tempo instance
- Traces without X-Tenant or with other values are stored in the green Tempo instance
- All routing rules function correctly and traces reach their intended destinations

## 🧹 Cleanup

The test runs in the `chainsaw-routecnctr` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses conditional routing based on trace attributes for multi-tenant scenarios
- Supports default routing for traces that don't match specific conditions
- Demonstrates fan-out from single input to multiple output pipelines
- Each routing rule can target different processing pipelines and exporters
- Enables tenant isolation by routing traces to separate backend systems 