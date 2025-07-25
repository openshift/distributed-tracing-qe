# Forward Connector - Pipeline Data Forwarding

This blueprint demonstrates how to use the OpenTelemetry Forward Connector to consolidate multiple data pipelines into a single output pipeline. This is essential for complex data processing scenarios where you need to apply different processing logic to different data sources before combining them.

## 🎯 Use Case

- **Pipeline Consolidation**: Combine multiple input pipelines into a single output pipeline
- **Data Flow Control**: Apply different processing logic to different data sources
- **Resource Optimization**: Reduce the number of exporters by consolidating outputs
- **Complex Routing**: Implement sophisticated data routing patterns
- **Pipeline Flexibility**: Maintain separation of concerns while enabling data consolidation

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with forward connector and multiple pipelines
- **Multiple OTLP Receivers**: Different endpoints for different data sources
- **Attribute Processors**: Add pipeline-specific tags to track data flow
- **Trace Generators**: Sample applications generating traces on different endpoints

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Understanding of OpenTelemetry pipeline concepts

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace forwardconnector-demo

# Set as current namespace
kubectl config set-context --current --namespace=forwardconnector-demo
```

### Step 2: Deploy OpenTelemetry Collector with Forward Connector

Create the collector configuration:

```yaml
# otel-forward-connector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otlp-forward-connector
  namespace: forwardconnector-demo
spec:
  mode: deployment
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  
  config:
    receivers:
      # Blue pipeline receiver (default HTTP port 4318)
      otlp/blue:
        protocols:
          http:
            endpoint: 0.0.0.0:4318
          grpc:
            endpoint: 0.0.0.0:4317
      
      # Green pipeline receiver (custom HTTP port 4319)
      otlp/green:
        protocols:
          http:
            endpoint: 0.0.0.0:4319
          grpc:
            endpoint: 0.0.0.0:4320
    
    processors:
      # Add blue pipeline tag
      attributes/blue:
        actions:
        - key: otel_pipeline_tag
          value: "blue"
          action: insert
        - key: pipeline.source
          value: "blue-endpoint"
          action: insert
      
      # Add green pipeline tag
      attributes/green:
        actions:
        - key: otel_pipeline_tag
          value: "green"
          action: insert
        - key: pipeline.source
          value: "green-endpoint"
          action: insert
      
      # Batch processor for the consolidated pipeline
      batch:
        timeout: 1s
        send_batch_size: 1024
        send_batch_max_size: 2048
      
      # Memory limiter for resource management
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
      
      # Transform processor to add metadata
      transform:
        trace_statements:
        - context: span
          statements:
          - set(attributes["processed_at"], Now())
          - set(attributes["collector.name"], "forward-connector-demo")
    
    connectors:
      # Forward connector to consolidate pipelines
      forward:
        # Optional configuration for the forward connector
        # (most configurations use default settings)
    
    exporters:
      # Debug exporter to see consolidated results
      debug:
        verbosity: detailed
      
      # Optional: Add other exporters as needed
      # logging:
      #   loglevel: info
      # otlp:
      #   endpoint: "downstream-collector:4317"
      #   insecure: true
    
    service:
      pipelines:
        # Blue input pipeline
        traces/blue:
          receivers: [otlp/blue]
          processors: [memory_limiter, attributes/blue]
          exporters: [forward]
        
        # Green input pipeline  
        traces/green:
          receivers: [otlp/green]
          processors: [memory_limiter, attributes/green]
          exporters: [forward]
        
        # Consolidated output pipeline
        traces:
          receivers: [forward]
          processors: [transform, batch]
          exporters: [debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

Apply the collector:

```bash
kubectl apply -f otel-forward-connector.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 3: Verify Collector Services

Check that the collector exposes multiple endpoints:

```bash
# Check collector services
kubectl get svc -l app.kubernetes.io/component=opentelemetry-collector

# Check service endpoints
kubectl get endpoints -l app.kubernetes.io/component=opentelemetry-collector

# Verify port configuration
kubectl describe svc otlp-forward-connector-collector
```

### Step 4: Generate Sample Traces on Different Pipelines

Create jobs to generate traces on different endpoints:

```yaml
# generate-traces.yaml
---
# Generate traces for BLUE pipeline (port 4318)
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces-http-blue
  namespace: forwardconnector-demo
spec:
  template:
    spec:
      containers:
      - name: telemetrygen-blue
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        args:
        - traces
        - --otlp-endpoint=otlp-forward-connector-collector:4318
        - --traces=10
        - --otlp-http
        - --otlp-insecure=true
        - --service=telemetrygen-http-blue
        - --otlp-attributes=protocol="otlp-http-blue",environment="staging"
        - --span-name=lets-go
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never
  backoffLimit: 4

---
# Generate traces for GREEN pipeline (port 4319)
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces-http-green
  namespace: forwardconnector-demo
spec:
  template:
    spec:
      containers:
      - name: telemetrygen-green
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        args:
        - traces
        - --otlp-endpoint=otlp-forward-connector-collector:4319
        - --traces=10
        - --otlp-http
        - --otlp-insecure=true
        - --service=telemetrygen-http-green
        - --otlp-attributes=protocol="otlp-http-green",environment="production"
        - --span-name=okey-dokey
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never
  backoffLimit: 4
```

Apply the trace generators:

```bash
kubectl apply -f generate-traces.yaml

# Monitor the jobs
kubectl get jobs -w

# Check job logs
kubectl logs job/generate-traces-http-blue
kubectl logs job/generate-traces-http-green
```

### Step 5: Verify Forward Connector Functionality

Check the collector logs to verify that traces from both pipelines are being consolidated:

```bash
# Check collector logs for consolidated traces
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=100

# Look for blue pipeline traces
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "blue"

# Look for green pipeline traces  
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "green"

# Look for span names from both pipelines
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -E "(lets-go|okey-dokey)"
```

### Step 6: Run Verification Script

Create an automated verification script:

```bash
# Create verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking forward connector functionality..."

# Define the label selector and namespace
LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=${NAMESPACE:-forwardconnector-demo}

# Define the search strings to verify both pipelines
SEARCH_STRINGS=(
  "otel_pipeline_tag: Str(blue)"
  "otel_pipeline_tag: Str(green)" 
  "Name           : lets-go"
  "Name           : okey-dokey"
)

# Get the collector pods
PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "❌ No collector pods found with label $LABEL_SELECTOR in namespace $NAMESPACE"
    exit 1
fi

echo "Found ${#PODS[@]} collector pod(s): ${PODS[*]}"

# Initialize flags to track if strings are found
declare -A found_flags
for string in "${SEARCH_STRINGS[@]}"; do
    found_flags["$string"]=false
done

echo "Searching for traces in collector logs..."

# Loop through each pod and search for the strings in the logs
for POD in "${PODS[@]}"; do
    echo "Checking pod: $POD"
    
    # Get logs from the pod
    LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=400 2>/dev/null || echo "")
    
    # Search for each string
    for STRING in "${SEARCH_STRINGS[@]}"; do
        if [ "${found_flags[$STRING]}" = false ] && echo "$LOGS" | grep -q -- "$STRING"; then
            echo "✅ \"$STRING\" found in $POD"
            found_flags["$STRING"]=true
        fi
    done
done

# Check if all strings were found
all_found=true
for STRING in "${SEARCH_STRINGS[@]}"; do
    if [ "${found_flags[$STRING]}" = false ]; then
        echo "❌ \"$STRING\" not found in any collector pod"
        all_found=false
    fi
done

if [ "$all_found" = true ]; then
    echo "🎉 Forward connector verification completed successfully!"
    echo "✅ Found traces from both blue and green pipelines"
    echo "✅ Pipeline tags are correctly applied"
    echo "✅ Span names from both pipelines are present"
else
    echo "❌ Forward connector verification failed"
    exit 1
fi
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Multiple Signal Types

Forward different types of telemetry data:

```yaml
service:
  pipelines:
    # Traces pipelines
    traces/frontend:
      receivers: [otlp/frontend]
      processors: [attributes/frontend]
      exporters: [forward]
    
    traces/backend:
      receivers: [otlp/backend] 
      processors: [attributes/backend]
      exporters: [forward]
    
    # Consolidated traces pipeline
    traces:
      receivers: [forward]
      processors: [batch]
      exporters: [debug, jaeger]
    
    # Metrics pipelines
    metrics/app:
      receivers: [otlp/app]
      processors: [attributes/app]
      exporters: [forward/metrics]
    
    metrics/infra:
      receivers: [prometheus]
      processors: [attributes/infra]
      exporters: [forward/metrics]
    
    # Consolidated metrics pipeline
    metrics:
      receivers: [forward/metrics]
      processors: [batch]
      exporters: [prometheus/remote_write]
```

### Conditional Processing

Apply different processing based on attributes:

```yaml
processors:
  attributes/conditional:
    actions:
    - key: priority
      value: "high"
      action: insert
      # Only apply to spans with specific service names
      include:
        match_type: regexp
        services: ["payment.*", "auth.*"]
  
  filter/sensitive:
    traces:
      span:
        # Filter out debug spans from production
        - 'attributes["debug"] == true and resource.attributes["env"] == "prod"'
```

### Fan-out Pattern

Use multiple forward connectors for different purposes:

```yaml
connectors:
  forward/analytics:
    # Forward to analytics pipeline
  forward/monitoring:
    # Forward to monitoring pipeline

service:
  pipelines:
    traces/input:
      receivers: [otlp]
      processors: [batch]
      exporters: [forward/analytics, forward/monitoring]
    
    traces/analytics:
      receivers: [forward/analytics]
      processors: [transform/analytics]
      exporters: [otlp/analytics_system]
    
    traces/monitoring:
      receivers: [forward/monitoring]
      processors: [filter/errors_only]
      exporters: [alertmanager]
```

### Resource Tagging

Add resource-specific attributes:

```yaml
processors:
  resource/blue:
    attributes:
    - key: pipeline.tier
      value: "frontend"
      action: insert
    - key: cluster.region
      value: "us-east-1"
      action: insert
  
  resource/green:
    attributes:
    - key: pipeline.tier
      value: "backend"
      action: insert  
    - key: cluster.region
      value: "us-west-2"
      action: insert
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector status
kubectl get opentelemetrycollector otlp-forward-connector

# Check all pipeline endpoints
kubectl get svc otlp-forward-connector-collector -o yaml

# Test endpoint connectivity
kubectl port-forward svc/otlp-forward-connector-collector 4318:4318 &
kubectl port-forward svc/otlp-forward-connector-collector 4319:4319 &
curl -v http://localhost:4318/v1/traces
curl -v http://localhost:4319/v1/traces
```

### Common Issues

**Issue: Data not appearing in consolidated pipeline**
```bash
# Check if forward connector is configured correctly
kubectl get opentelemetrycollector otlp-forward-connector -o yaml | grep -A 5 connectors

# Verify pipeline connections
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i forward
```

**Issue: Port conflicts**
```bash
# Check port assignments
kubectl describe svc otlp-forward-connector-collector

# Verify no port conflicts
netstat -tlnp | grep :4319
```

**Issue: High memory usage**
```bash
# Check resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Adjust batch settings
kubectl patch opentelemetrycollector otlp-forward-connector --type='merge' -p='{"spec":{"config":"processors:\n  batch:\n    send_batch_size: 512"}}'
```

### Performance Monitoring

```bash
# Monitor collector metrics
kubectl port-forward svc/otlp-forward-connector-collector 8888:8888 &
curl http://localhost:8888/metrics | grep otelcol

# Check pipeline throughput
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -E "(received|exported)"
```

## 📊 Use Cases

### Multi-Environment Data Collection

Collect data from different environments:

```yaml
receivers:
  otlp/staging:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
  otlp/production:
    protocols:
      http:
        endpoint: 0.0.0.0:4319

processors:
  attributes/staging:
    actions:
    - key: environment
      value: "staging"
      action: insert
  attributes/production:
    actions:
    - key: environment 
      value: "production"
      action: insert
```

### Service Mesh Integration

Consolidate data from different service mesh components:

```yaml
receivers:
  otlp/istio:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
  otlp/linkerd:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4320

processors:
  attributes/mesh:
    actions:
    - key: mesh.type
      from_attribute: "service.mesh"
      action: insert
```

### Application Tier Separation

Separate frontend and backend data processing:

```yaml
processors:
  filter/frontend:
    traces:
      span:
        - 'resource.attributes["service.tier"] != "frontend"'
  
  filter/backend:
    traces:
      span:
        - 'resource.attributes["service.tier"] != "backend"'
```

## 🔐 Security Considerations

1. **Endpoint Isolation**: Use different ports for different security zones
2. **Data Segregation**: Ensure sensitive data doesn't mix between pipelines
3. **Resource Limits**: Set appropriate limits for each pipeline
4. **Network Policies**: Restrict access to specific endpoints

## 📚 Related Patterns

- [routingconnector](../routingconnector/) - For conditional data routing
- [countconnector](../countconnector/) - For data volume monitoring
- [transformprocessor](../transformprocessor/) - For data transformation

## 🧹 Cleanup

```bash
# Remove trace generation jobs
kubectl delete job generate-traces-http-blue generate-traces-http-green

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector otlp-forward-connector

# Remove namespace
kubectl delete namespace forwardconnector-demo
```

## 📖 Additional Resources

- [OpenTelemetry Forward Connector Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/forwardconnector)
- [OpenTelemetry Pipeline Configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Connector Components Overview](https://opentelemetry.io/docs/collector/configuration/#connectors) 