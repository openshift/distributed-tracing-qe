# Count Connector - Telemetry Data Metrics Generation

This blueprint demonstrates how to use the OpenTelemetry Count Connector to generate metrics based on the volume of telemetry data (logs, metrics, and traces) flowing through your OpenTelemetry Collector. This is essential for monitoring your observability infrastructure and understanding data throughput.

## 🎯 Use Case

- **Data Volume Monitoring**: Track the amount of telemetry data flowing through your collectors
- **Pipeline Health**: Monitor the health and throughput of your telemetry pipelines
- **Cost Management**: Understand data volume for cost optimization decisions
- **Capacity Planning**: Plan infrastructure scaling based on telemetry data patterns
- **SLA Monitoring**: Ensure telemetry data collection meets service level agreements

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with count connector and Prometheus exporter
- **User Workload Monitoring**: OpenShift monitoring stack for custom metrics
- **Telemetry Data Generators**: Sample applications generating logs, metrics, and traces
- **Prometheus Integration**: Metrics exposed for monitoring and alerting

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- OpenShift User Workload Monitoring enabled (for OpenShift)
- Access to monitoring APIs

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace countconnector-demo

# Set as current namespace
kubectl config set-context --current --namespace=countconnector-demo
```

### Step 2: Enable User Workload Monitoring (OpenShift)

For OpenShift clusters, enable user workload monitoring:

```yaml
# workload-monitoring.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```

Apply the monitoring configuration:

```bash
oc apply -f workload-monitoring.yaml

# Wait for user workload monitoring to be enabled
oc wait --for=condition=Available deployment/prometheus-operator -n openshift-user-workload-monitoring --timeout=300s
```

### Step 3: Deploy OpenTelemetry Collector with Count Connector

Create the collector configuration:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: count
  namespace: countconnector-demo
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  
  # Enable metrics collection for the collector itself
  observability:
    metrics:
      enableMetrics: true
  
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
      # Batch processing for efficiency
      batch:
        timeout: 1s
        send_batch_size: 1024
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
    
    connectors:
      # Count connector to generate metrics from telemetry data
      count:
        # Count logs and create metrics
        logs:
          dev.log.count:
            description: "The number of logs from each environment"
            attributes:
              - key: telemetrygentype
                default_value: unspecified_environment
              - key: service.name
                default_value: unknown_service
        
        # Count metric data points
        datapoints:
          dev.metrics.datapoint:
            description: "The number of metric datapoints from each environment"
            attributes:
              - key: telemetrygentype
                default_value: unspecified_environment
              - key: service.name
                default_value: unknown_service
        
        # Count spans/traces
        spans:
          dev.span.count:
            description: "The number of spans from each environment"
            attributes:
              - key: telemetrygentype
                default_value: unspecified_environment
              - key: service.name
                default_value: unknown_service
    
    exporters:
      # Debug exporter for troubleshooting
      debug:
        verbosity: basic
      
      # Prometheus exporter for metrics
      prometheus:
        endpoint: 0.0.0.0:8889
        resource_to_telemetry_conversion:
          enabled: true  # Include resource attributes as labels
    
    service:
      pipelines:
        # Input pipelines - receive telemetry data and send to count connector
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [count]
        
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [count]
        
        logs:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [count]
        
        # Output pipeline - receive count metrics and export them
        metrics/count:
          receivers: [count]
          processors: [batch]
          exporters: [prometheus, debug]
```

Apply the collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 4: Set Up RBAC for Monitoring Access

Create necessary permissions for accessing metrics:

```yaml
# monitoring-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: countconnector-metrics-api
rules:
- apiGroups: ["monitoring.coreos.com"]
  resources: ["prometheuses/api"]
  verbs: ["get", "list", "watch", "create"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: countconnector-metrics-api
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: countconnector-metrics-api
subjects:
- kind: ServiceAccount
  name: prometheus-user-workload
  namespace: openshift-user-workload-monitoring
```

Apply the RBAC configuration:

```bash
kubectl apply -f monitoring-rbac.yaml
```

### Step 5: Generate Sample Telemetry Data

Create jobs to generate different types of telemetry data:

```yaml
# generate-telemetry-data.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces
  namespace: countconnector-demo
spec:
  template:
    spec:
      containers:
      - name: telemetrygen
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        args:
        - traces
        - --otlp-endpoint=count-collector:4317
        - --otlp-insecure=true
        - --traces=5
        - "--otlp-attributes=telemetrygentype=\"traces\""
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
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-metrics
  namespace: countconnector-demo
spec:
  template:
    spec:
      containers:
      - name: telemetrygen
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        args:
        - metrics
        - --otlp-endpoint=count-collector:4317
        - --otlp-insecure=true
        - --metrics=5
        - "--otlp-attributes=telemetrygentype=\"metrics\""
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
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-logs
  namespace: countconnector-demo
spec:
  template:
    spec:
      containers:
      - name: telemetrygen
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        args:
        - logs
        - --otlp-endpoint=count-collector:4317
        - --otlp-insecure=true
        - --logs=5
        - "--otlp-attributes=telemetrygentype=\"logs\""
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

Apply the telemetry generators:

```bash
kubectl apply -f generate-telemetry-data.yaml

# Monitor the jobs
kubectl get jobs
kubectl logs job/generate-traces -f
kubectl logs job/generate-metrics -f
kubectl logs job/generate-logs -f
```

### Step 6: Verify Count Metrics

Check that count metrics are being generated:

```bash
# Check collector logs for count metrics
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=50

# Access Prometheus metrics endpoint directly
kubectl port-forward svc/count-collector 8889:8889 &
curl http://localhost:8889/metrics | grep dev_
```

### Step 7: Query Metrics via OpenShift Monitoring

Create a verification script for OpenShift:

```bash
# Create verification script
cat > check_metrics.sh << 'EOF'
#!/bin/bash
set -e

# Get token for authentication
TOKEN=$(oc create token prometheus-user-workload -n openshift-user-workload-monitoring)
THANOS_QUERIER_HOST=$(oc get route thanos-querier -n openshift-monitoring -o json | jq -r '.spec.host')

# Define the expected metrics and their values
declare -A metrics_map
metrics_map["dev_log_count_total{telemetrygentype=\"logs\"}"]=1
metrics_map["dev_metrics_datapoint_total{telemetrygentype=\"metrics\"}"]=1  
metrics_map["dev_span_count_total{telemetrygentype=\"traces\"}"]=10
metrics_map["metric_count_total{telemetrygentype=\"metrics\"}"]=1

echo "Checking count connector metrics..."

# Check each metric
for metric in "${!metrics_map[@]}"; do
  expected_value="${metrics_map[$metric]}"
  actual_value=0
  max_attempts=30
  attempt=0

  echo "Checking metric: $metric (expected: $expected_value)"
  
  while [[ "$actual_value" != "$expected_value" && $attempt -lt $max_attempts ]]; do
    response=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
      --data-urlencode "query=${metric}" \
      "https://$THANOS_QUERIER_HOST/api/v1/query")
    
    actual_value=$(echo "$response" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    if [[ "$actual_value" != "$expected_value" ]]; then
      echo "  Attempt $((attempt+1)): Actual value: '${actual_value}', retrying..."
      sleep 5
      ((attempt++))
    else
      echo "  ✓ Metric '$metric' has expected value: $expected_value"
    fi
  done
  
  if [[ $attempt -eq $max_attempts ]]; then
    echo "  ✗ Metric '$metric' did not reach expected value after $max_attempts attempts"
    exit 1
  fi
done

echo "All count connector metrics verified successfully!"
EOF

chmod +x check_metrics.sh
./check_metrics.sh
```

## 🔧 Advanced Configuration

### Custom Count Metrics

Configure more specific count metrics:

```yaml
connectors:
  count:
    logs:
      error.log.count:
        description: "Count of error logs"
        attributes:
          - key: severity_text
            default_value: unknown
        conditions:
          - key: severity_text
            value: "ERROR"
    
    spans:
      http.request.count:
        description: "Count of HTTP requests"
        attributes:
          - key: http.method
            default_value: unknown
          - key: http.status_code
            default_value: unknown
        conditions:
          - key: span.kind
            value: "SPAN_KIND_SERVER"
```

### Multiple Count Connectors

Use multiple count connectors for different purposes:

```yaml
connectors:
  count/errors:
    logs:
      error.count:
        description: "Error log count"
        conditions:
          - key: severity_text
            value: "ERROR"
  
  count/performance:
    spans:
      slow.spans.count:
        description: "Slow span count"
        conditions:
          - key: duration_ms
            operator: ">"
            value: 1000

service:
  pipelines:
    logs/errors:
      receivers: [otlp]
      exporters: [count/errors]
    
    traces/performance:
      receivers: [otlp]
      exporters: [count/performance]
```

### Rate Calculations

Combine with other processors for rate calculations:

```yaml
processors:
  transform:
    metric_statements:
    - context: metric
      statements:
      # Calculate rate of logs per minute
      - set(description, "Log rate per minute") where name == "dev_log_count_total"
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector status
kubectl get opentelemetrycollector count

# Check metrics endpoint
kubectl port-forward svc/count-collector 8889:8889 &
curl http://localhost:8889/metrics

# Check generated jobs
kubectl get jobs
```

### Common Issues

**Issue: No count metrics generated**
```bash
# Check if telemetry data is reaching the collector
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "received"

# Verify count connector configuration
kubectl get opentelemetrycollector count -o yaml | grep -A 20 connectors
```

**Issue: Metrics not appearing in Prometheus**
```bash
# Check Prometheus exporter logs
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep prometheus

# Verify service monitor if using operator
kubectl get servicemonitor
```

**Issue: Authentication errors with monitoring**
```bash
# Recreate service account token
oc create token prometheus-user-workload -n openshift-user-workload-monitoring

# Check RBAC permissions
oc auth can-i get prometheuses/api --as=system:serviceaccount:openshift-user-workload-monitoring:prometheus-user-workload
```

## 📊 Use Cases

### Data Volume Monitoring

Monitor telemetry data volume across different services:

```yaml
connectors:
  count:
    logs:
      service.log.volume:
        attributes:
          - key: service.name
            default_value: unknown
          - key: service.version
            default_value: unknown
```

### Error Rate Tracking

Track error rates across your services:

```yaml
connectors:
  count:
    logs:
      error.rate:
        conditions:
          - key: severity_text
            value: "ERROR"
        attributes:
          - key: service.name
```

### Performance Monitoring

Monitor slow traces and requests:

```yaml
connectors:
  count:
    spans:
      slow.requests:
        conditions:
          - key: duration_ms
            operator: ">"
            value: 5000
```

## 🔐 Security Considerations

1. **RBAC Configuration**: Ensure minimal required permissions
2. **Token Management**: Regularly rotate service account tokens
3. **Network Policies**: Restrict access to metrics endpoints
4. **Resource Limits**: Set appropriate limits to prevent resource exhaustion

## 📚 Related Patterns

- [groupbyattrsprocessor](../groupbyattrsprocessor/) - For attribute-based grouping
- [prometheusremotewriteexporter](../prometheusremotewriteexporter/) - For Prometheus integration
- [filterprocessor](../filterprocessor/) - For conditional data processing

## 🧹 Cleanup

```bash
# Remove telemetry generation jobs
kubectl delete job generate-traces generate-metrics generate-logs

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector count

# Remove RBAC configuration
kubectl delete clusterrole countconnector-metrics-api
kubectl delete clusterrolebinding countconnector-metrics-api

# Remove monitoring configuration (optional)
oc delete configmap cluster-monitoring-config -n openshift-monitoring

# Remove namespace
kubectl delete namespace countconnector-demo
```

## 📖 Additional Resources

- [OpenTelemetry Count Connector Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/countconnector)
- [OpenShift User Workload Monitoring](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html)
- [Prometheus Metrics](https://prometheus.io/docs/concepts/metric_types/) 