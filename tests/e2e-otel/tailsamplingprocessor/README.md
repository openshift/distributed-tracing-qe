# Tail Sampling Processor - Intelligent Trace Sampling for Cost Optimization

This blueprint demonstrates how to use the OpenTelemetry Tail Sampling processor to implement intelligent, context-aware trace sampling that reduces storage costs while preserving critical observability data.

## 🎯 Use Case

- **Cost Optimization**: Reduce trace storage and processing costs by intelligent sampling
- **Performance Optimization**: Lower system overhead while maintaining observability
- **Error Preservation**: Always keep traces containing errors or anomalies
- **Smart Filtering**: Sample based on trace characteristics rather than random chance
- **SLA Monitoring**: Preserve traces that impact service level objectives

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with tail sampling processor
- **Tempo Backend**: Trace storage and visualization
- **Sample Applications**: Generate diverse traces for sampling demonstration
- **Monitoring Dashboard**: Observe sampling effectiveness

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured

### Step 1: Create Namespace

```bash
# Create dedicated namespace
kubectl create namespace tailsampling-demo

# Set as current namespace
kubectl config set-context --current --namespace=tailsampling-demo
```

### Step 2: Deploy Tempo Backend

Create Tempo instance for trace storage:

```yaml
# tempo-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: tailsampling-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tempo
  template:
    metadata:
      labels:
        app: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:2.3.0
        args:
        - "-config.file=/etc/tempo/tempo.yaml"
        - "-mem-ballast-size-mbs=1024"
        ports:
        - containerPort: 3200
          name: http
        - containerPort: 4317
          name: otlp-grpc
        - containerPort: 4318
          name: otlp-http
        volumeMounts:
        - name: tempo-config
          mountPath: /etc/tempo
        - name: tempo-storage
          mountPath: /tmp/tempo
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: tempo-config
        configMap:
          name: tempo-config
      - name: tempo-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: tailsampling-demo
spec:
  selector:
    app: tempo
  ports:
  - name: http
    port: 3200
    targetPort: 3200
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
  - name: otlp-http
    port: 4318
    targetPort: 4318
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: tailsampling-demo
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
      grpc_listen_port: 9095

    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318

    ingester:
      max_block_duration: 5m

    compactor:
      compaction:
        block_retention: 24h

    storage:
      trace:
        backend: local
        local:
          path: /tmp/tempo/traces
        wal:
          path: /tmp/tempo/wal

    query_frontend:
      search:
        duration_slo: 5s
        throughput_bytes_slo: 1.073741824e+09
      trace_by_id:
        duration_slo: 5s
```

Apply Tempo deployment:

```bash
kubectl apply -f tempo-deployment.yaml

# Wait for Tempo to be ready
kubectl wait --for=condition=available deployment/tempo --timeout=300s
```

### Step 3: Deploy OpenTelemetry Collector with Tail Sampling

Create a collector configuration with sophisticated tail sampling policies:

```yaml
# tailsampling-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: tailsampling-collector
  namespace: tailsampling-demo
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      # Memory limiter to prevent OOM
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 15
      
      # Batch processor for efficiency
      batch:
        timeout: 5s
        send_batch_size: 1024
      
      # Tail sampling processor with multiple policies
      tail_sampling:
        # Wait time before making sampling decision
        decision_wait: 10s
        
        # Expected number of new traces per second
        expected_new_traces_per_sec: 100
        
        # Maximum number of traces to keep in memory
        num_traces: 10000
        
        policies:
        # Policy 1: Always sample traces with errors
        - name: errors-policy
          type: status_code
          status_code:
            status_codes: [ERROR]
        
        # Policy 2: Always sample slow traces (> 5 seconds)
        - name: slow-traces-policy
          type: latency
          latency:
            threshold_ms: 5000
        
        # Policy 3: Sample traces from critical services at 100%
        - name: critical-services-policy
          type: string_attribute
          string_attribute:
            key: service.name
            values: ["payment-service", "auth-service", "order-service"]
        
        # Policy 4: Sample traces with specific operations at higher rate
        - name: important-operations-policy
          type: string_attribute
          string_attribute:
            key: operation.name
            values: ["login", "checkout", "payment"]
        
        # Policy 5: Sample traces with high-value customers
        - name: vip-customers-policy
          type: string_attribute
          string_attribute:
            key: customer.tier
            values: ["premium", "enterprise"]
        
        # Policy 6: Probabilistic sampling for normal traces (10%)
        - name: probabilistic-policy
          type: probabilistic
          probabilistic:
            sampling_percentage: 10.0
        
        # Policy 7: Rate limiting sampling (max 50 traces per second)
        - name: rate-limit-policy
          type: rate_limiting
          rate_limiting:
            spans_per_second: 50
        
        # Policy 8: Numeric attribute-based sampling (sample expensive operations)
        - name: expensive-operations-policy
          type: numeric_attribute
          numeric_attribute:
            key: operation.cost
            min_value: 1000
            max_value: 999999
        
        # Policy 9: Composite policy (errors OR slow traces from specific services)
        - name: composite-policy
          type: composite
          composite:
            max_total_spans_per_second: 100
            policy_order: [critical-services-policy, errors-policy, slow-traces-policy]
            composite_sub_policy:
            - name: critical-and-errors
              type: and
              and:
                and_sub_policy:
                - name: critical-service-check
                  type: string_attribute
                  string_attribute:
                    key: service.name
                    values: ["user-service", "notification-service"]
                - name: error-check
                  type: status_code
                  status_code:
                    status_codes: [ERROR]
        
        # Policy 10: Trace state-based sampling
        - name: trace-state-policy
          type: trace_state
          trace_state:
            key: "sampling"
            values: ["high-priority", "debug"]
        
        # Policy 11: Boolean attribute sampling
        - name: debug-flag-policy
          type: boolean_attribute
          boolean_attribute:
            key: debug.enabled
            value: true
      
      # Resource attributes processor
      resource:
        attributes:
        - key: cluster.name
          value: "tailsampling-demo"
          action: upsert
        - key: sampling.strategy
          value: "tail-sampling"
          action: upsert
    
    exporters:
      # Export to Tempo
      otlp:
        endpoint: "tempo.tailsampling-demo.svc:4317"
        tls:
          insecure: true
      
      # Debug exporter to see sampling decisions
      debug:
        verbosity: basic
      
      # Metrics for monitoring sampling effectiveness
      prometheus:
        endpoint: "0.0.0.0:8889"
        namespace: "tailsampling"
        resource_to_telemetry_conversion:
          enabled: true
    
    service:
      telemetry:
        metrics:
          address: 0.0.0.0:8888
      
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, tail_sampling, resource, batch]
          exporters: [otlp, debug]
        
        # Separate pipeline for metrics (sampling metrics)
        metrics:
          receivers: []
          processors: [batch]
          exporters: [prometheus]
```

Apply the tail sampling collector:

```bash
kubectl apply -f tailsampling-collector.yaml

# Wait for collector to be ready
kubectl wait --for=condition=available deployment/tailsampling-collector-collector --timeout=300s
```

### Step 4: Deploy Diverse Trace Generators

Create applications that generate different types of traces to demonstrate sampling:

```yaml
# trace-generators.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: normal-service-generator
  namespace: tailsampling-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: normal-service-generator
  template:
    metadata:
      labels:
        app: normal-service-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://tailsampling-collector-collector.tailsampling-demo.svc:4318"
          
          while true; do
            TRACE_ID=$(openssl rand -hex 16)
            SPAN_ID=$(openssl rand -hex 8)
            
            # Generate normal traces (should be sampled at 10%)
            curl -X POST ${OTEL_ENDPOINT}/v1/traces \
              -H "Content-Type: application/json" \
              -d '{
                "resourceSpans": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "catalog-service"}
                    }]
                  },
                  "scopeSpans": [{
                    "spans": [{
                      "traceId": "'$TRACE_ID'",
                      "spanId": "'$SPAN_ID'",
                      "name": "get_products",
                      "kind": 1,
                      "startTimeUnixNano": "'$(date +%s%N)'",
                      "endTimeUnixNano": "'$(($(date +%s%N) + $((RANDOM % 500 + 50)) * 1000000))'",
                      "status": {"code": 1},
                      "attributes": [{
                        "key": "http.method",
                        "value": {"stringValue": "GET"}
                      }, {
                        "key": "customer.tier",
                        "value": {"stringValue": "standard"}
                      }]
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Normal service trace sent"
            sleep 2
          done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: critical-service-generator
  namespace: tailsampling-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: critical-service-generator
  template:
    metadata:
      labels:
        app: critical-service-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://tailsampling-collector-collector.tailsampling-demo.svc:4318"
          
          while true; do
            TRACE_ID=$(openssl rand -hex 16)
            SPAN_ID=$(openssl rand -hex 8)
            
            # Generate traces from critical services (should be sampled at 100%)
            curl -X POST ${OTEL_ENDPOINT}/v1/traces \
              -H "Content-Type: application/json" \
              -d '{
                "resourceSpans": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "payment-service"}
                    }]
                  },
                  "scopeSpans": [{
                    "spans": [{
                      "traceId": "'$TRACE_ID'",
                      "spanId": "'$SPAN_ID'",
                      "name": "process_payment",
                      "kind": 1,
                      "startTimeUnixNano": "'$(date +%s%N)'",
                      "endTimeUnixNano": "'$(($(date +%s%N) + $((RANDOM % 1000 + 100)) * 1000000))'",
                      "status": {"code": 1},
                      "attributes": [{
                        "key": "operation.name",
                        "value": {"stringValue": "payment"}
                      }, {
                        "key": "customer.tier",
                        "value": {"stringValue": "premium"}
                      }, {
                        "key": "operation.cost",
                        "value": {"doubleValue": '$((RANDOM % 2000 + 500))'}
                      }]
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Critical service trace sent"
            sleep 3
          done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: error-generator
  namespace: tailsampling-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: error-generator
  template:
    metadata:
      labels:
        app: error-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://tailsampling-collector-collector.tailsampling-demo.svc:4318"
          
          while true; do
            TRACE_ID=$(openssl rand -hex 16)
            SPAN_ID=$(openssl rand -hex 8)
            
            # Generate error traces (should always be sampled)
            curl -X POST ${OTEL_ENDPOINT}/v1/traces \
              -H "Content-Type: application/json" \
              -d '{
                "resourceSpans": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "user-service"}
                    }]
                  },
                  "scopeSpans": [{
                    "spans": [{
                      "traceId": "'$TRACE_ID'",
                      "spanId": "'$SPAN_ID'",
                      "name": "authenticate_user",
                      "kind": 1,
                      "startTimeUnixNano": "'$(date +%s%N)'",
                      "endTimeUnixNano": "'$(($(date +%s%N) + $((RANDOM % 200 + 50)) * 1000000))'",
                      "status": {"code": 2, "message": "Authentication failed"},
                      "attributes": [{
                        "key": "http.status_code",
                        "value": {"intValue": 401}
                      }, {
                        "key": "error.type",
                        "value": {"stringValue": "authentication_error"}
                      }]
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Error trace sent"
            sleep 8
          done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slow-trace-generator
  namespace: tailsampling-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: slow-trace-generator
  template:
    metadata:
      labels:
        app: slow-trace-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://tailsampling-collector-collector.tailsampling-demo.svc:4318"
          
          while true; do
            TRACE_ID=$(openssl rand -hex 16)
            SPAN_ID=$(openssl rand -hex 8)
            
            # Generate slow traces (should always be sampled)
            DURATION=$((RANDOM % 10000 + 6000))  # 6-16 seconds
            START_TIME=$(date +%s%N)
            END_TIME=$((START_TIME + DURATION * 1000000))
            
            curl -X POST ${OTEL_ENDPOINT}/v1/traces \
              -H "Content-Type: application/json" \
              -d '{
                "resourceSpans": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "search-service"}
                    }]
                  },
                  "scopeSpans": [{
                    "spans": [{
                      "traceId": "'$TRACE_ID'",
                      "spanId": "'$SPAN_ID'",
                      "name": "complex_search",
                      "kind": 1,
                      "startTimeUnixNano": "'$START_TIME'",
                      "endTimeUnixNano": "'$END_TIME'",
                      "status": {"code": 1},
                      "attributes": [{
                        "key": "query.complexity",
                        "value": {"stringValue": "high"}
                      }, {
                        "key": "duration.ms",
                        "value": {"doubleValue": '$DURATION'}
                      }]
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Slow trace sent (${DURATION}ms)"
            sleep 15
          done
```

Apply trace generators:

```bash
kubectl apply -f trace-generators.yaml

# Wait for generators to be ready
kubectl wait --for=condition=available deployment/normal-service-generator --timeout=300s
kubectl wait --for=condition=available deployment/critical-service-generator --timeout=300s
kubectl wait --for=condition=available deployment/error-generator --timeout=300s
kubectl wait --for=condition=available deployment/slow-trace-generator --timeout=300s
```

### Step 5: Verify Tail Sampling

Check sampling decisions and effectiveness:

```bash
# Check collector logs for sampling decisions
kubectl logs deployment/tailsampling-collector-collector -f --tail=100

# Check Tempo for received traces
kubectl port-forward svc/tempo 3200:3200 &

# Query Tempo for traces
curl "http://localhost:3200/api/search" | jq '.'

# Check sampling metrics
kubectl port-forward svc/tailsampling-collector-collector 8889:8889 &
curl "http://localhost:8889/metrics" | grep tailsampling
```

### Step 6: Run Sampling Verification Script

```bash
# Create verification script
cat > check_tail_sampling.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking Tail Sampling functionality..."

# Wait for sampling to process traces
sleep 120

# Get collector pod name
COLLECTOR_POD=$(kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}')

if [ -z "$COLLECTOR_POD" ]; then
    echo "ERROR: No collector pod found"
    exit 1
fi

echo "Using collector pod: $COLLECTOR_POD"

# Check for sampling decisions in logs
echo "Checking sampling decisions..."

# Check for different policy triggers
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "errors-policy"
if [ $? -eq 0 ]; then
    echo "✓ Error-based sampling policy active"
else
    echo "✗ Error-based sampling policy not found"
fi

kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "slow-traces-policy"
if [ $? -eq 0 ]; then
    echo "✓ Latency-based sampling policy active"
else
    echo "✗ Latency-based sampling policy not found"
fi

kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "critical-services-policy"
if [ $? -eq 0 ]; then
    echo "✓ Critical services sampling policy active"
else
    echo "✗ Critical services sampling policy not found"
fi

# Check for probabilistic sampling
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "probabilistic-policy"
if [ $? -eq 0 ]; then
    echo "✓ Probabilistic sampling policy active"
else
    echo "✗ Probabilistic sampling policy not found"
fi

# Check that some traces are being sampled and others dropped
SAMPLED_COUNT=$(kubectl logs $COLLECTOR_POD --tail=2000 | grep -c "Sampled" || true)
DROPPED_COUNT=$(kubectl logs $COLLECTOR_POD --tail=2000 | grep -c "Dropped\|NotSampled" || true)

echo "Sampled traces: $SAMPLED_COUNT"
echo "Dropped traces: $DROPPED_COUNT"

if [ "$SAMPLED_COUNT" -gt 0 ]; then
    echo "✓ Tail sampling is working - traces are being sampled"
else
    echo "✗ No sampled traces found"
fi

if [ "$DROPPED_COUNT" -gt 0 ]; then
    echo "✓ Tail sampling is working - traces are being dropped"
else
    echo "✗ No dropped traces found"
fi

# Check Tempo for stored traces
echo "Checking Tempo for stored traces..."
kubectl port-forward svc/tempo 3200:3200 &
FORWARD_PID=$!
sleep 5

TEMPO_TRACES=$(curl -s "http://localhost:3200/api/search" | jq -r '.traces | length' 2>/dev/null || echo "0")

if [ "$TEMPO_TRACES" != "null" ] && [ "$TEMPO_TRACES" -gt 0 ]; then
    echo "✓ Traces found in Tempo: $TEMPO_TRACES"
else
    echo "✗ No traces found in Tempo"
fi

# Clean up port forward
kill $FORWARD_PID 2>/dev/null || true

echo "Tail sampling verification completed!"
EOF

chmod +x check_tail_sampling.sh
./check_tail_sampling.sh
```

## 🔧 Advanced Sampling Strategies

### Smart Sampling Based on Business Value

```yaml
processors:
  tail_sampling:
    policies:
    # High-value transactions
    - name: high-value-transactions
      type: numeric_attribute
      numeric_attribute:
        key: transaction.amount
        min_value: 1000.0
    
    # VIP customers always sampled
    - name: vip-customers
      type: string_attribute
      string_attribute:
        key: customer.id
        values: ["vip_001", "vip_002", "enterprise_123"]
    
    # Geographic sampling
    - name: apac-region-sampling
      type: string_attribute
      string_attribute:
        key: geo.region
        values: ["ap-southeast-1", "ap-northeast-1"]
```

### Dynamic Sampling Rates

```yaml
processors:
  tail_sampling:
    policies:
    # Different rates for different environments
    - name: production-sampling
      type: and
      and:
        and_sub_policy:
        - name: env-check
          type: string_attribute
          string_attribute:
            key: deployment.environment
            values: ["production"]
        - name: prob-sampling
          type: probabilistic
          probabilistic:
            sampling_percentage: 5.0  # Lower rate for production
    
    - name: staging-sampling
      type: and
      and:
        and_sub_policy:
        - name: env-check
          type: string_attribute
          string_attribute:
            key: deployment.environment
            values: ["staging"]
        - name: prob-sampling
          type: probabilistic
          probabilistic:
            sampling_percentage: 25.0  # Higher rate for staging
```

### Composite Sampling Logic

```yaml
processors:
  tail_sampling:
    policies:
    # Complex OR logic: Sample if ANY condition is true
    - name: important-traces
      type: composite
      composite:
        max_total_spans_per_second: 1000
        policy_order: [errors, slow-traces, critical-services, vip-users]
        rate_allocation:
        - policy: errors
          percent: 40
        - policy: slow-traces
          percent: 30
        - policy: critical-services
          percent: 20
        - policy: vip-users
          percent: 10
```

## 🔍 Monitoring Sampling Effectiveness

### Key Metrics to Track

```bash
# Sampling rate metrics
otelcol_processor_tail_sampling_count_traces_sampled
otelcol_processor_tail_sampling_count_traces_not_sampled

# Policy effectiveness
otelcol_processor_tail_sampling_policy_evaluation_count

# Memory usage for trace buffers
otelcol_processor_tail_sampling_traces_on_memory

# Decision latency
otelcol_processor_tail_sampling_sampling_decision_latency
```

### Cost Analysis

```bash
# Create cost analysis script
cat > analyze_sampling_cost.sh << 'EOF'
#!/bin/bash

echo "Analyzing sampling cost effectiveness..."

# Get metrics
kubectl port-forward svc/tailsampling-collector-collector 8889:8889 &
FORWARD_PID=$!
sleep 5

# Calculate sampling rate
SAMPLED=$(curl -s http://localhost:8889/metrics | grep "otelcol_processor_tail_sampling_count_traces_sampled" | grep -v "#" | awk '{print $2}' | tail -1)
NOT_SAMPLED=$(curl -s http://localhost:8889/metrics | grep "otelcol_processor_tail_sampling_count_traces_not_sampled" | grep -v "#" | awk '{print $2}' | tail -1)

TOTAL=$((SAMPLED + NOT_SAMPLED))
if [ "$TOTAL" -gt 0 ]; then
    SAMPLING_RATE=$(echo "scale=2; $SAMPLED * 100 / $TOTAL" | bc)
    REDUCTION=$(echo "scale=2; 100 - $SAMPLING_RATE" | bc)
    
    echo "Total traces processed: $TOTAL"
    echo "Traces sampled: $SAMPLED"
    echo "Traces dropped: $NOT_SAMPLED"
    echo "Sampling rate: ${SAMPLING_RATE}%"
    echo "Cost reduction: ${REDUCTION}%"
else
    echo "No traces processed yet"
fi

kill $FORWARD_PID 2>/dev/null || true
EOF

chmod +x analyze_sampling_cost.sh
./analyze_sampling_cost.sh
```

## 🚨 Troubleshooting

### Low Sampling Rate Issues

```bash
# Check policy configuration
kubectl get opentelemetrycollector tailsampling-collector -o yaml | grep -A 50 "tail_sampling"

# Check decision wait time
kubectl logs deployment/tailsampling-collector-collector | grep "decision_wait"

# Monitor trace buffer
kubectl port-forward svc/tailsampling-collector-collector 8888:8888 &
curl http://localhost:8888/metrics | grep "traces_on_memory"
```

### High Memory Usage

```bash
# Check trace buffer size
kubectl logs deployment/tailsampling-collector-collector | grep -i "memory\|buffer"

# Monitor resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Adjust buffer size
kubectl patch opentelemetrycollector tailsampling-collector --type='merge' -p='{"spec":{"config":"processors:\n  tail_sampling:\n    num_traces: 5000"}}'
```

### Missing Traces

```bash
# Check if critical traces are being preserved
kubectl logs deployment/tailsampling-collector-collector | grep -i "error\|critical"

# Verify policy order
kubectl logs deployment/tailsampling-collector-collector | grep "policy_order"

# Check for policy conflicts
kubectl logs deployment/tailsampling-collector-collector | grep -i "conflict\|override"
```

## 🔐 Security and Compliance

### Data Retention Policies

```yaml
processors:
  tail_sampling:
    policies:
    # Compliance: Always sample financial transactions
    - name: financial-compliance
      type: string_attribute
      string_attribute:
        key: transaction.type
        values: ["payment", "refund", "transfer"]
    
    # PII protection: Sample with data anonymization
    - name: pii-protection
      type: and
      and:
        and_sub_policy:
        - name: has-pii
          type: boolean_attribute
          boolean_attribute:
            key: contains.pii
            value: true
        - name: anonymized
          type: boolean_attribute
          boolean_attribute:
            key: data.anonymized
            value: true
```

## 📊 Configuration Examples

### Policy Configuration

1. **Order Matters**: Place more specific policies before general ones
2. **Performance**: Use lightweight policies for high-traffic scenarios
3. **Monitoring**: Always include metrics for policy effectiveness
4. **Testing**: Validate policies in test environments before deployment

### Resource Management

```yaml
processors:
  tail_sampling:
    # Tune for your traffic patterns
    decision_wait: 10s        # Balance between accuracy and latency
    num_traces: 50000         # Based on expected TPS and decision_wait
    expected_new_traces_per_sec: 1000  # Help size internal buffers
```

## 📚 Related Patterns

- [transformprocessor](../transformprocessor/) - For data transformation before sampling
- [filterprocessor](../filterprocessor/) - For pre-filtering data
- [loadbalancingexporter](../loadbalancingexporter/) - For distributing sampled traces

## 🧹 Cleanup

```bash
# Remove trace generators
kubectl delete deployment normal-service-generator critical-service-generator error-generator slow-trace-generator

# Remove tail sampling collector
kubectl delete opentelemetrycollector tailsampling-collector

# Remove Tempo
kubectl delete deployment tempo
kubectl delete service tempo
kubectl delete configmap tempo-config

# Remove namespace
kubectl delete namespace tailsampling-demo
``` 