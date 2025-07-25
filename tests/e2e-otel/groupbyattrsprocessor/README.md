# Group By Attributes Processor - Metric Aggregation and Cardinality Management

This blueprint demonstrates how to use the OpenTelemetry Group By Attributes Processor to group metrics by specific attributes, reduce cardinality, and optimize metric storage and querying. This is essential for managing high-cardinality metrics and improving monitoring system performance.

## 🎯 Use Case

- **Cardinality Reduction**: Group similar metrics to reduce overall metric cardinality
- **Resource Optimization**: Aggregate metrics by meaningful dimensions for better resource utilization
- **Cost Management**: Reduce storage and processing costs by intelligent metric grouping
- **Query Performance**: Improve query performance by pre-aggregating metrics
- **Data Organization**: Structure metrics in meaningful hierarchies for better analysis

## 📋 What You'll Deploy

- **Kubelet Stats Collector DaemonSet**: Collects container and node metrics from kubelet
- **Main Collector with Group By Processor**: Applies grouping logic to incoming metrics
- **Service Account & RBAC**: Permissions for kubelet stats access
- **Prometheus Exporter**: Exports grouped metrics to Prometheus format
- **OpenShift User Workload Monitoring**: For metrics collection and verification

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- OpenShift User Workload Monitoring enabled (for OpenShift)
- Access to cluster monitoring APIs

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace groupbyattrsprocessor-demo

# Set as current namespace
kubectl config set-context --current --namespace=groupbyattrsprocessor-demo
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

### Step 3: Create Service Account and RBAC

Create permissions for kubelet stats access:

```yaml
# rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: groupbyattrs-sa
  namespace: groupbyattrsprocessor-demo

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: groupbyattrs-role
rules:
# Access to kubelet stats
- apiGroups: [""]
  resources: ["nodes/stats"]
  verbs: ["get", "watch", "list"]

# Access to kubelet proxy
- apiGroups: [""]
  resources: ["nodes/proxy"]  
  verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: groupbyattrs-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: groupbyattrs-role
subjects:
- kind: ServiceAccount
  name: groupbyattrs-sa
  namespace: groupbyattrsprocessor-demo
```

Apply the RBAC configuration:

```bash
kubectl apply -f rbac.yaml
```

### Step 4: Deploy Main Collector with Group By Attributes Processor

Create the main collector that will process and group metrics:

```yaml
# otel-groupbyattributes.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: gba-main
  namespace: groupbyattrsprocessor-demo
spec:
  mode: deployment
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  
  # Enable metrics for the collector itself
  observability:
    metrics:
      enableMetrics: true
  
  config:
    receivers:
      # OTLP receiver for metrics from DaemonSet collectors
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      # Group by attributes processor - primary feature
      groupbyattrs:
        # Keys to group metrics by
        keys:
        - k8s.namespace.name
        - k8s.container.name
        - k8s.pod.name
        
        # Optional: Additional grouping configurations
        # drop_non_grouped_metrics: false
        # reduce_cardinality: true
      
      # Batch processor for efficiency
      batch:
        timeout: 30s
        send_batch_size: 1024
        send_batch_max_size: 2048
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
      
      # Attributes processor to add pipeline metadata
      attributes:
        actions:
        - key: otelpipeline
          value: gba
          action: insert
        - key: processor.type
          value: groupbyattrs
          action: insert
      
      # Resource processor for additional metadata
      resource:
        attributes:
        - key: cluster.name
          value: "groupbyattrs-demo-cluster"
          action: upsert
        - key: pipeline.stage
          value: "grouped"
          action: upsert
    
    exporters:
      # Prometheus exporter for metrics
      prometheus:
        endpoint: 0.0.0.0:8889
        resource_to_telemetry_conversion:
          enabled: true  # Include resource attributes as labels
        namespace: "otelcol"
        const_labels:
          pipeline: "groupbyattrs"
      
      # Debug exporter for troubleshooting
      debug:
        verbosity: basic
    
    service:
      pipelines:
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, attributes, batch, groupbyattrs]
          exporters: [prometheus, debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

Apply the main collector:

```bash
kubectl apply -f otel-groupbyattributes.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 5: Deploy Kubelet Stats Collector DaemonSet

Create the DaemonSet collector to gather kubelet metrics:

```yaml
# otel-collector-daemonset.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: kubeletstats-gba
  namespace: groupbyattrsprocessor-demo
spec:
  mode: daemonset
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: groupbyattrs-sa
  
  # Environment variables for node-specific configuration
  env:
  - name: K8S_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
  
  config:
    receivers:
      # Kubelet stats receiver
      kubeletstats:
        collection_interval: 30s
        auth_type: "serviceAccount"
        endpoint: "https://${env:K8S_NODE_NAME}:10250"
        insecure_skip_verify: true
        
        # Extra metadata for grouping
        extra_metadata_labels:
        - container.id
        - k8s.volume.type
        
        # Metric groups to collect
        metric_groups:
        - container
        - pod
        - node
    
    processors:
      # Batch processor for efficiency
      batch:
        timeout: 10s
        send_batch_size: 1024
      
      # Resource processor to add node information
      resource:
        attributes:
        - key: node.name
          value: "${env:K8S_NODE_NAME}"
          action: upsert
        - key: collector.type
          value: "daemonset"
          action: upsert
    
    exporters:
      # Forward to main collector
      otlp:
        endpoint: gba-main-collector:4317
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
    
    service:
      pipelines:
        metrics:
          receivers: [kubeletstats]
          processors: [resource, batch]
          exporters: [otlp]
  
  # Tolerations to run on all nodes
  tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  - operator: Exists
    effect: NoExecute
  - operator: Exists
    effect: NoSchedule
  
  # Node selector
  nodeSelector:
    kubernetes.io/os: linux
```

Apply the DaemonSet collector:

```bash
kubectl apply -f otel-collector-daemonset.yaml

# Wait for the DaemonSet to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kubeletstats-gba --timeout=300s
```

### Step 6: Create Monitoring View Role (OpenShift)

For OpenShift, create a role for monitoring access:

```yaml
# monitoring-view-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-view-role
rules:
- apiGroups: ["monitoring.coreos.com"]
  resources: ["prometheuses/api"]
  verbs: ["get", "list", "watch", "create"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: monitoring-view-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: monitoring-view-role
subjects:
- kind: ServiceAccount
  name: prometheus-user-workload
  namespace: openshift-user-workload-monitoring
```

Apply the monitoring role:

```bash
kubectl apply -f monitoring-view-role.yaml
```

### Step 7: Verify Metric Collection and Grouping

Check that metrics are being collected and grouped:

```bash
# Check main collector logs
kubectl logs -l app.kubernetes.io/name=gba-main --tail=50

# Check DaemonSet collector logs
kubectl logs -l app.kubernetes.io/name=kubeletstats-gba --tail=50

# Check Prometheus metrics endpoint
kubectl port-forward svc/gba-main-collector 8889:8889 &
curl http://localhost:8889/metrics | grep -E "(groupbyattrs|otelcol)"
```

### Step 8: Run Verification Script

Create and run verification script for OpenShift monitoring:

```bash
# Create verification script
cat > check_metrics.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking group by attributes processor functionality..."

# Get authentication token for OpenShift monitoring
TOKEN=$(oc create token prometheus-user-workload -n openshift-user-workload-monitoring 2>/dev/null || echo "")
THANOS_QUERIER_HOST=$(oc get route thanos-querier -n openshift-monitoring -o json 2>/dev/null | jq -r '.spec.host' || echo "")

if [ -z "$TOKEN" ] || [ -z "$THANOS_QUERIER_HOST" ] || [ "$THANOS_QUERIER_HOST" = "null" ]; then
    echo "⚠️  OpenShift monitoring not available, checking collector metrics directly..."
    
    # Port forward to collector metrics endpoint
    kubectl port-forward svc/gba-main-collector 8889:8889 &
    PF_PID=$!
    sleep 5
    
    # Check for group by attributes processor metrics
    echo "Checking collector metrics endpoint..."
    
    if curl -s http://localhost:8889/metrics | grep -q "otelcol_processor_groupbyattrs"; then
        echo "✅ Group by attributes processor metrics found"
    else
        echo "❌ Group by attributes processor metrics not found"
        kill $PF_PID 2>/dev/null || true
        exit 1
    fi
    
    # Cleanup
    kill $PF_PID 2>/dev/null || true
    echo "🎉 Basic verification completed successfully!"
    exit 0
fi

echo "Using OpenShift monitoring for verification..."

# Define expected group by attributes processor metrics
metrics=(
    "otelcol_processor_groupbyattrs_num_non_grouped_metrics_ratio_total"
    "otelcol_processor_groupbyattrs_metric_groups_ratio_bucket"
    "otelcol_processor_groupbyattrs_metric_groups_ratio_count"
    "otelcol_processor_groupbyattrs_metric_groups_ratio_sum"
)

# Check each metric
for metric in "${metrics[@]}"; do
    echo "Checking metric: $metric"
    count=0
    max_attempts=30
    attempt=0

    # Keep fetching until metric with value is present
    while [[ $count -eq 0 && $attempt -lt $max_attempts ]]; do
        response=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
            -H "Content-type: application/json" \
            "https://$THANOS_QUERIER_HOST/api/v1/query?query=$metric" 2>/dev/null || echo "{}")
        
        count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null || echo "0")

        if [[ $count -eq 0 ]]; then
            echo "  Attempt $((attempt+1)): No metric '$metric' with value present. Retrying..."
            sleep 5
            ((attempt++))
        else
            echo "  ✅ Metric '$metric' with value is present."
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        echo "  ❌ Metric '$metric' not found after $max_attempts attempts"
        exit 1
    fi
done

echo "🎉 Group by attributes processor verification completed successfully!"
echo "✅ All expected processor metrics found"
echo "✅ Metric grouping is functioning correctly"
EOF

chmod +x check_metrics.sh
./check_metrics.sh
```

## 🔧 Advanced Configuration

### Custom Grouping Keys

Group by different attribute combinations:

```yaml
processors:
  groupbyattrs/namespace:
    keys:
    - k8s.namespace.name
    
  groupbyattrs/service:
    keys:
    - service.name
    - service.version
    
  groupbyattrs/node:
    keys:
    - k8s.node.name
    - node.zone
```

### Conditional Grouping

Apply different grouping based on metric characteristics:

```yaml
processors:
  groupbyattrs/high_cardinality:
    keys:
    - k8s.namespace.name
    - k8s.pod.name
    reduce_cardinality: true
    
  groupbyattrs/low_cardinality:
    keys:
    - k8s.namespace.name
    reduce_cardinality: false
```

### Drop Non-Grouped Metrics

Remove metrics that don't match grouping criteria:

```yaml
processors:
  groupbyattrs:
    keys:
    - k8s.namespace.name
    - k8s.container.name
    drop_non_grouped_metrics: true
```

### Multiple Grouping Stages

Apply grouping in multiple stages:

```yaml
service:
  pipelines:
    metrics/stage1:
      receivers: [otlp]
      processors: [groupbyattrs/namespace]
      exporters: [otlp/stage2]
    
    metrics/stage2:
      receivers: [otlp/stage2]
      processors: [groupbyattrs/service]
      exporters: [prometheus]
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector status
kubectl get opentelemetrycollector gba-main kubeletstats-gba

# Check DaemonSet distribution
kubectl get pods -l app.kubernetes.io/name=kubeletstats-gba -o wide

# Check metric pipeline connectivity
kubectl logs -l app.kubernetes.io/name=gba-main | grep -i "otlp.*received"
```

### Common Issues

**Issue: Metrics not being grouped**
```bash
# Check group by attributes processor configuration
kubectl get opentelemetrycollector gba-main -o yaml | grep -A 10 groupbyattrs

# Verify grouping keys exist in metrics
kubectl logs -l app.kubernetes.io/name=gba-main | grep -E "(k8s\.namespace\.name|k8s\.container\.name)"
```

**Issue: High cardinality still present**
```bash
# Check processor metrics
kubectl port-forward svc/gba-main-collector 8889:8889 &
curl http://localhost:8889/metrics | grep groupbyattrs_metric_groups_ratio

# Adjust grouping keys
kubectl patch opentelemetrycollector gba-main --type='merge' -p='{"spec":{"config":"processors:\n  groupbyattrs:\n    keys:\n    - k8s.namespace.name"}}'
```

**Issue: Performance degradation**
```bash
# Check processor performance metrics
kubectl logs -l app.kubernetes.io/name=gba-main | grep -i "groupbyattrs.*latency"

# Monitor resource usage
kubectl top pods -l app.kubernetes.io/name=gba-main
```

### Performance Monitoring

```bash
# Monitor grouping effectiveness
kubectl logs -l app.kubernetes.io/name=gba-main | grep "groupbyattrs" | grep "ratio"

# Check metric volume before and after grouping
kubectl port-forward svc/gba-main-collector 8889:8889 &
curl -s http://localhost:8889/metrics | grep -c "^otelcol"
```

## 📊 Grouping Strategies

### Namespace-Based Grouping

Group metrics by Kubernetes namespace for multi-tenant environments:

```yaml
processors:
  groupbyattrs/namespace:
    keys:
    - k8s.namespace.name
    - k8s.cluster.name
```

### Service-Based Grouping

Group by service for application-centric monitoring:

```yaml
processors:
  groupbyattrs/service:
    keys:
    - service.name
    - service.version
    - deployment.environment
```

### Resource-Based Grouping

Group by resource type for infrastructure monitoring:

```yaml
processors:
  groupbyattrs/resource:
    keys:
    - k8s.resource.kind
    - k8s.namespace.name
    - resource.tier
```

### Geographic Grouping

Group by location for distributed systems:

```yaml
processors:
  groupbyattrs/location:
    keys:
    - cloud.region
    - cloud.availability_zone
    - datacenter.name
```

## 🔐 Security Considerations

1. **RBAC Permissions**: Grant minimal required permissions for kubelet access
2. **Metric Filtering**: Filter sensitive metrics before grouping
3. **Resource Limits**: Set appropriate limits to prevent resource exhaustion
4. **Network Policies**: Restrict collector communication as needed

## 📚 Related Patterns

- [kubeletstatsreceiver](../kubeletstatsreceiver/) - For source metrics collection
- [prometheusremotewriteexporter](../prometheusremotewriteexporter/) - For metrics export
- [transformprocessor](../transformprocessor/) - For metric transformation

## 🧹 Cleanup

```bash
# Remove OpenTelemetry collectors
kubectl delete opentelemetrycollector gba-main kubeletstats-gba

# Remove RBAC configuration
kubectl delete clusterrolebinding groupbyattrs-binding monitoring-view-binding
kubectl delete clusterrole groupbyattrs-role monitoring-view-role
kubectl delete serviceaccount groupbyattrs-sa

# Remove monitoring configuration (optional)
oc delete configmap cluster-monitoring-config -n openshift-monitoring

# Remove namespace
kubectl delete namespace groupbyattrsprocessor-demo
```

## 📖 Additional Resources

- [OpenTelemetry Group By Attributes Processor Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/groupbyattrsprocessor)
- [Metric Cardinality Guidelines](https://opentelemetry.io/docs/specs/otel/metrics/data-model/#cardinality-limits)
- [OpenShift User Workload Monitoring](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html) 