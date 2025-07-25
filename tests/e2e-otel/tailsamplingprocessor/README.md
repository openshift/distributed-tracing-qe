# OpenTelemetry Tail Sampling Processor Test

This test demonstrates the OpenTelemetry Tail Sampling processor configuration for intelligent trace sampling based on complete trace information.

## 🎯 What This Test Does

The test validates that the Tail Sampling processor can:
- Wait for complete trace spans before making sampling decisions
- Apply multiple sampling policies (status code, latency, span count, service name)
- Forward sampled traces to Tempo for storage and verification
- Process traces from both generated telemetry and HotROD application

## 📋 Test Resources

### 1. Tempo Monolithic Instance
```yaml
apiVersion: tempo.grafana.com/v1alpha1
kind: TempoMonolithic
metadata:
  name: tailsmp
spec:
  jaegerui:
    enabled: true
```

### 2. OpenTelemetry Collector with Tail Sampling Processor
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: tailsmp
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
      otlp:
        endpoint: tempo-tailsmp:4317
        tls:
          insecure: true

    processors:
      tail_sampling:
        decision_wait: 30s
        num_traces: 50000
        expected_new_traces_per_sec: 20
        policies:
          [
            {
              name: status-code-policy,
              type: status_code,
              status_code: {status_codes: [ERROR]}
            },
            {
              name: latency-policy,
              type: latency,
              latency: {threshold_ms: 5000, upper_threshold_ms: 10000}
            },
            {
                name: span-count-policy,
                type: span_count,
                span_count: {min_spans: 39, max_spans: 50}
            },
            {
                name: service-name-policy,
                type: string_attribute,
                string_attribute:
                {
                  key: service.name,
                  values: [customer],
                },
            },
          ]
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [tail_sampling]
          exporters: [otlp,debug]
```

### 3. HotROD Application Deployment
The test deploys the HotROD (Rides on Demand) demo application which generates realistic traces with various characteristics for testing the sampling policies.

### 4. Trace Generators
- HotROD traffic generation to create traces with different patterns
- Telemetrygen job to create additional test traces

## 🚀 Test Steps

1. **Create Tempo Instance** - Deploy Tempo monolithic instance for trace storage
2. **Check Tempo Status** - Verify Tempo instance is ready
3. **Create OTEL Collector** - Deploy collector with tail sampling processor
4. **Install HotROD App** - Deploy the rides-on-demand demo application
5. **Generate HotROD Traces** - Create traffic to generate realistic traces
6. **Generate Additional Traces** - Send more traces using telemetrygen
7. **Verify Traces** - Check that sampled traces are received in Tempo

## 🔍 Sampling Policies Applied

### 1. Status Code Policy
- **Name**: `status-code-policy`
- **Type**: `status_code`
- **Rule**: Sample traces with ERROR status codes
- **Purpose**: Ensure all error traces are captured

### 2. Latency Policy
- **Name**: `latency-policy`
- **Type**: `latency`
- **Rule**: Sample traces with latency between 5000ms and 10000ms
- **Purpose**: Capture slow but not extremely slow requests

### 3. Span Count Policy
- **Name**: `span-count-policy`
- **Type**: `span_count`
- **Rule**: Sample traces with 39-50 spans
- **Purpose**: Focus on complex traces with many operations

### 4. Service Name Policy
- **Name**: `service-name-policy`
- **Type**: `string_attribute`
- **Rule**: Sample traces from services named "customer"
- **Purpose**: Ensure traces from critical service are sampled

## 🔧 Configuration Parameters

- **Decision Wait**: 30 seconds - Time to wait for complete trace before sampling decision
- **Num Traces**: 50,000 - Maximum number of traces to keep in memory
- **Expected New Traces Per Sec**: 20 - Expected trace rate for memory management
- **Policy Evaluation**: OR logic - Trace is sampled if ANY policy matches

## 🧹 Cleanup

The test runs in the `chainsaw-tailsmp` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses tail-based sampling requiring complete trace information before decisions
- Multiple policies with OR logic - any matching policy triggers sampling
- Integrates with Tempo for trace storage and Jaeger UI for verification
- Handles both generated telemetry and realistic application traces
- Balances comprehensive error capture with selective sampling of normal traces 