# Filter Processor - Selective Telemetry Data Processing

This blueprint demonstrates how to use the OpenTelemetry Filter Processor to selectively drop or include telemetry data based on specific conditions. This is essential for reducing data volume, controlling costs, and focusing on relevant observability data.

## 🎯 Use Case

- **Data Volume Reduction**: Drop irrelevant or noisy telemetry data
- **Cost Optimization**: Reduce storage and processing costs by filtering unnecessary data
- **Environment Separation**: Filter data based on environments (dev, staging, prod)
- **Quality Control**: Remove incomplete or malformed telemetry data
- **Privacy Compliance**: Filter out sensitive information from logs and traces

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with filter processor and debug exporter
- **Telemetry Data Generators**: Sample applications generating different types of data
- **Filter Rules**: Examples of span, metric, and log filtering
- **Verification Scripts**: Automated checks to confirm filtering behavior

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Understanding of OpenTelemetry data model

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace filterprocessor-demo

# Set as current namespace
kubectl config set-context --current --namespace=filterprocessor-demo
```

### Step 2: Deploy OpenTelemetry Collector with Filter Processor

Create the collector configuration:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: filterprocessor
  namespace: filterprocessor-demo
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  
  config:
    receivers:
      # OTLP receiver for incoming telemetry data
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      # Filter processor with different filtering rules
      filter:
        # Error handling mode: ignore, propagate, or silent
        error_mode: ignore
        
        # Span/trace filtering rules
        traces:
          span:
            # Drop spans with red environment attribute
            - 'attributes["traces-env"] == "red"'
            # Drop spans from resources with red color
            - 'resource.attributes["traces-colour"] == "red"'
            
        # Metric filtering rules  
        metrics:
          metric:
            # Drop metrics named "gen" from red resources
            - 'name == "gen" and resource.attributes["metrics-colour"] == "red"'
            
        # Log filtering rules
        logs:
          log_record:
            # Drop logs containing "drop message" in body
            - 'IsMatch(body, "drop message")'
      
      # Additional processors for enhanced filtering
      batch:
        timeout: 1s
        send_batch_size: 1024
      
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
    
    exporters:
      # Debug exporter to see filtered results
      debug:
        verbosity: detailed
        
      # Additional exporters as needed
      # logging:
      #   loglevel: info
    
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, filter, batch]
          exporters: [debug]
          
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, filter, batch]
          exporters: [debug]
          
        logs:
          receivers: [otlp]
          processors: [memory_limiter, filter, batch]
          exporters: [debug]
```

Apply the collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 3: Generate Sample Telemetry Data

Create jobs to generate telemetry data with different attributes for testing the filter:

```yaml
# generate-telemetry-data.yaml
---
# Generate RED traces (will be filtered out)
apiVersion: batch/v1
kind: Job
metadata:
  name: traces-red
  namespace: filterprocessor-demo
spec:
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        app: traces-red
    spec:
      containers:
      - name: traces-red
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - "--otlp-endpoint=filterprocessor-collector:4318"
        - "--otlp-http"
        - "--otlp-insecure=true"
        - "--traces=5"
        - "--otlp-attributes=traces-colour=\"red\""
        - "--otlp-header=traces-envtype=\"devenv\""
        - "--telemetry-attributes=traces-env=\"red\""
        - "--service=red-service"
        - "traces"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never

---
# Generate GREEN traces (will be kept)
apiVersion: batch/v1
kind: Job
metadata:
  name: traces-green
  namespace: filterprocessor-demo
spec:
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        app: traces-green
    spec:
      containers:
      - name: traces-green
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - "--otlp-endpoint=filterprocessor-collector:4318"
        - "--otlp-http"
        - "--otlp-insecure=true"
        - "--traces=5"
        - "--otlp-attributes=traces-colour=\"green\""
        - "--otlp-header=traces-envtype=\"prodenv\""
        - "--telemetry-attributes=traces-env=\"prod\""
        - "--service=green-service"
        - "traces"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never

---
# Generate RED metrics (will be filtered out)
apiVersion: batch/v1
kind: Job
metadata:
  name: metrics-red
  namespace: filterprocessor-demo
spec:
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        app: metrics-red
    spec:
      containers:
      - name: metrics-red
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - "--otlp-endpoint=filterprocessor-collector:4318"
        - "--otlp-http"
        - "--otlp-insecure=true"
        - "--metrics=5"
        - "--otlp-attributes=metrics-colour=\"red\""
        - "--otlp-header=metrics-envtype=\"devenv\""
        - "--telemetry-attributes=metrics-env=\"dev\""
        - "metrics"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never

---
# Generate GREEN metrics (will be kept)
apiVersion: batch/v1
kind: Job
metadata:
  name: metrics-green
  namespace: filterprocessor-demo
spec:
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        app: metrics-green
    spec:
      containers:
      - name: metrics-green
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - "--otlp-endpoint=filterprocessor-collector:4318"
        - "--otlp-http"
        - "--otlp-insecure=true"
        - "--metrics=5"
        - "--otlp-attributes=metrics-colour=\"green\""
        - "--otlp-header=metrics-envtype=\"prodenv\""
        - "--telemetry-attributes=metrics-env=\"prod\""
        - "metrics"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never

---
# Generate RED logs (will be filtered out - contains "drop message")
apiVersion: batch/v1
kind: Job
metadata:
  name: logs-red
  namespace: filterprocessor-demo
spec:
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        app: logs-red
    spec:
      containers:
      - name: logs-red
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - "--otlp-endpoint=filterprocessor-collector:4318"
        - "--otlp-http"
        - "--otlp-insecure=true"
        - "--logs=5"
        - "--body=\"drop message\""
        - "--otlp-attributes=logs-colour=\"red\""
        - "--otlp-header=logs-envtype=\"devenv\""
        - "--telemetry-attributes=logs-env=\"dev\""
        - "logs"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never

---
# Generate GREEN logs (will be kept)
apiVersion: batch/v1
kind: Job
metadata:
  name: logs-green
  namespace: filterprocessor-demo
spec:
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        app: logs-green
    spec:
      containers:
      - name: logs-green
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - "--otlp-endpoint=filterprocessor-collector:4318"
        - "--otlp-http"
        - "--otlp-insecure=true"
        - "--logs=5"
        - "--otlp-attributes=logs-colour=\"green\""
        - "--otlp-header=logs-envtype=\"prodenv\""
        - "--telemetry-attributes=logs-env=\"prod\""
        - "logs"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never
```

Apply the telemetry generators:

```bash
kubectl apply -f generate-telemetry-data.yaml

# Monitor the jobs
kubectl get jobs -w

# Wait for all jobs to complete
kubectl wait --for=condition=complete job --all --timeout=300s
```

### Step 4: Verify Filtering Behavior

Check the collector logs to verify that only "green" telemetry data is processed:

```bash
# Check collector logs for filtered results
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=100

# Look for green data (should be present)
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "green"

# Look for red data (should be absent)
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "red" || echo "No red data found (correct)"
```

### Step 5: Run Verification Script

Create an automated verification script:

```bash
# Create verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking filter processor functionality..."

# Define the label selector and namespace
LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=${NAMESPACE:-filterprocessor-demo}

# Define the expected search strings (green data should be present)
EXPECTED_STRINGS=(
  "logs-colour: Str(green)"
  "metrics-colour: Str(green)"
  "traces-colour: Str(green)"
)

# Define the prohibited search strings (red data should be filtered out)
PROHIBITED_STRINGS=(
  "logs-colour: Str(red)"
  "metrics-colour: Str(red)"
  "traces-colour: Str(red)"
)

# Get the collector pod
PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "❌ No collector pods found with label $LABEL_SELECTOR in namespace $NAMESPACE"
    exit 1
fi

POD=${PODS[0]}
echo "Using collector pod: $POD"

# Get all logs from the collector pod
echo "Fetching logs from collector..."
LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=-1)

echo "Checking for expected (green) data..."
# Check for expected strings (green data should be present)
for STRING in "${EXPECTED_STRINGS[@]}"; do
    if echo "$LOGS" | grep -q -- "$STRING"; then
        echo "✅ \"$STRING\" found in $POD (expected)"
    else
        echo "❌ \"$STRING\" not found in $POD (should be present)"
        exit 1
    fi
done

echo "Checking for prohibited (red) data..."
# Check for prohibited strings (red data should be filtered out)
for PROHIBITED_STRING in "${PROHIBITED_STRINGS[@]}"; do
    if echo "$LOGS" | grep -q -- "$PROHIBITED_STRING"; then
        echo "❌ \"$PROHIBITED_STRING\" found in $POD (should be filtered out)"
        exit 1
    else
        echo "✅ \"$PROHIBITED_STRING\" correctly filtered out"
    fi
done

echo "🎉 Filter processor verification completed successfully!"
echo "✅ All green data was processed"
echo "✅ All red data was correctly filtered out"
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Attribute-Based Filtering

Filter based on specific attribute values:

```yaml
processors:
  filter:
    traces:
      span:
        # Keep only HTTP spans
        - 'attributes["http.method"] == nil'
        # Drop slow spans
        - 'attributes["duration_ms"] > 5000'
        # Keep only successful requests
        - 'attributes["http.status_code"] >= 400'
```

### Resource-Based Filtering

Filter based on resource attributes:

```yaml
processors:
  filter:
    traces:
      span:
        # Filter by service name
        - 'resource.attributes["service.name"] == "debug-service"'
        # Filter by deployment environment
        - 'resource.attributes["deployment.environment"] != "production"'
```

### Complex Filtering Expressions

Use complex boolean logic:

```yaml
processors:
  filter:
    logs:
      log_record:
        # Drop debug logs from non-production environments
        - 'severity_text == "DEBUG" and resource.attributes["env"] != "prod"'
        # Keep only error logs or logs from critical services
        - 'severity_text != "ERROR" and resource.attributes["service.tier"] != "critical"'
```

### Regular Expression Filtering

Use regex patterns for filtering:

```yaml
processors:
  filter:
    logs:
      log_record:
        # Drop logs matching sensitive data patterns
        - 'IsMatch(body, "(?i)(password|secret|token)")'
        # Keep only logs from specific service patterns
        - 'not IsMatch(resource.attributes["service.name"], "^(api|web|db)-.*")'
```

### Multiple Filter Processors

Use multiple filter processors for different purposes:

```yaml
processors:
  filter/security:
    error_mode: propagate
    logs:
      log_record:
        - 'IsMatch(body, "(?i)(password|secret|api[_-]?key)")'
  
  filter/environment:
    error_mode: ignore
    traces:
      span:
        - 'resource.attributes["env"] == "test"'
    
  filter/performance:
    metrics:
      metric:
        - 'name == "debug_metric"'

service:
  pipelines:
    logs:
      receivers: [otlp]
      processors: [filter/security, filter/environment, batch]
      exporters: [debug]
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector status
kubectl get opentelemetrycollector filterprocessor

# Check pod logs for filter processor errors
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i filter

# Check resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector
```

### Common Issues

**Issue: Filter expressions not working**
```bash
# Check syntax of filter expressions
kubectl get opentelemetrycollector filterprocessor -o yaml | grep -A 10 filter

# Verify expression syntax in logs
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "filter.*error"
```

**Issue: Too much data being filtered**
```bash
# Check if error_mode is set correctly
kubectl get opentelemetrycollector filterprocessor -o yaml | grep error_mode

# Test with more permissive filters
kubectl patch opentelemetrycollector filterprocessor --type='merge' -p='{"spec":{"config":"processors:\n  filter:\n    error_mode: ignore"}}'
```

**Issue: Performance degradation**
```bash
# Check CPU and memory usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Simplify filter expressions
# Complex regex patterns can be expensive
```

### Filter Expression Testing

Test filter expressions locally:

```bash
# Use telemetrygen to test specific data patterns
kubectl run telemetrygen-test --rm -i --tty --image=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0 \
  -- /bin/sh -c "telemetrygen logs --logs=1 --body='test message' --otlp-endpoint=filterprocessor-collector:4318 --otlp-insecure"
```

## 📊 Filter Expression Examples

### Common Use Cases

**Drop test/debug data:**
```yaml
traces:
  span:
    - 'attributes["env"] == "test"'
    - 'attributes["debug"] == true'
```

**Keep only errors:**
```yaml
logs:
  log_record:
    - 'severity_text != "ERROR" and severity_text != "FATAL"'
```

**Filter by service:**
```yaml
metrics:
  metric:
    - 'resource.attributes["service.name"] not in ["critical-service", "payment-service"]'
```

**Content-based filtering:**
```yaml
logs:
  log_record:
    - 'IsMatch(body, "health.*check")'  # Drop health check logs
    - 'IsMatch(body, "heartbeat")'      # Drop heartbeat logs
```

## 🔐 Security Considerations

1. **Sensitive Data**: Use filters to remove sensitive information
2. **Resource Usage**: Monitor CPU/memory usage for complex filters
3. **Error Handling**: Set appropriate error_mode for your use case
4. **Access Control**: Restrict access to filter configurations

## 📚 Related Patterns

- [transformprocessor](../transformprocessor/) - For modifying data before filtering
- [groupbyattrsprocessor](../groupbyattrsprocessor/) - For attribute-based grouping
- [tailsamplingprocessor](../tailsamplingprocessor/) - For intelligent trace sampling

## 🧹 Cleanup

```bash
# Remove telemetry generation jobs
kubectl delete job traces-red traces-green metrics-red metrics-green logs-red logs-green

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector filterprocessor

# Remove namespace
kubectl delete namespace filterprocessor-demo
```

## 📖 Additional Resources

- [OpenTelemetry Filter Processor Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/filterprocessor)
- [Filter Expression Language](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/ottl/README.md)
- [OpenTelemetry Data Model](https://opentelemetry.io/docs/specs/otel/overview/) 