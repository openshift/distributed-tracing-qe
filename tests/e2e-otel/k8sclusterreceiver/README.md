# Kubernetes Cluster Receiver - Cluster-wide Metrics Collection

This blueprint demonstrates how to use the OpenTelemetry Kubernetes Cluster receiver to collect comprehensive metrics about your Kubernetes cluster, including pod states, node resources, and workload status.

## 🎯 Use Case

- **Cluster Monitoring**: Monitor overall cluster health and resource utilization
- **Workload Visibility**: Track deployment status, pod states, and resource consumption  
- **Capacity Planning**: Understand resource usage patterns and plan capacity
- **Troubleshooting**: Identify issues with pods, nodes, and cluster components
- **Cost Optimization**: Monitor resource allocation and identify optimization opportunities

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with Kubernetes cluster receiver
- **RBAC Configuration**: Service account with cluster-wide read permissions
- **Metrics Collection**: Pod metrics, node metrics, deployment status, and more
- **Debug Output**: View collected metrics for validation

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Cluster-admin permissions for RBAC setup

### Step 1: Create Namespace and RBAC

```bash
# Create dedicated namespace
kubectl create namespace k8scluster-demo

# Set as current namespace
kubectl config set-context --current --namespace=k8scluster-demo
```

Create comprehensive RBAC configuration:

```yaml
# rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k8s-cluster-receiver
  namespace: k8scluster-demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-cluster-receiver-role
rules:
# Core resources
- apiGroups: [""]
  resources:
  - events
  - namespaces
  - namespaces/status
  - nodes
  - nodes/spec
  - nodes/stats
  - nodes/proxy
  - pods
  - pods/status
  - replicationcontrollers
  - replicationcontrollers/status
  - resourcequotas
  - services
  - endpoints
  - persistentvolumes
  - persistentvolumeclaims
  - componentstatuses
  verbs: ["get", "list", "watch"]

# Apps resources
- apiGroups: ["apps"]
  resources:
  - daemonsets
  - deployments
  - replicasets
  - statefulsets
  verbs: ["get", "list", "watch"]

# Extensions resources
- apiGroups: ["extensions"]
  resources:
  - daemonsets
  - deployments
  - replicasets
  verbs: ["get", "list", "watch"]

# Batch resources
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs: ["get", "list", "watch"]

# Autoscaling resources
- apiGroups: ["autoscaling"]
  resources:
  - horizontalpodautoscalers
  verbs: ["get", "list", "watch"]

# Networking resources
- apiGroups: ["networking.k8s.io"]
  resources:
  - networkpolicies
  - ingresses
  verbs: ["get", "list", "watch"]

# Storage resources
- apiGroups: ["storage.k8s.io"]
  resources:
  - storageclasses
  - volumeattachments
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: k8s-cluster-receiver-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8s-cluster-receiver-role
subjects:
- kind: ServiceAccount
  name: k8s-cluster-receiver
  namespace: k8scluster-demo
```

Apply RBAC configuration:

```bash
kubectl apply -f rbac.yaml
```

### Step 2: Deploy OpenTelemetry Collector with K8s Cluster Receiver

Create the collector configuration:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: k8s-cluster-receiver
  namespace: k8scluster-demo
spec:
  serviceAccount: k8s-cluster-receiver
  
  config:
    receivers:
      k8s_cluster:
        # Collection interval
        collection_interval: 30s
        
        # Node conditions to report
        node_conditions_to_report:
        - Ready
        - MemoryPressure
        - DiskPressure
        - PIDPressure
        - NetworkUnavailable
        
        # Allocatable resource types to report
        allocatable_types_to_report:
        - cpu
        - memory
        - storage
        - ephemeral-storage
        
        # Metrics to collect
        metrics:
          k8s.namespace.phase:
            enabled: true
          k8s.node.condition:
            enabled: true
          k8s.pod.phase:
            enabled: true
          k8s.pod.status_reason:
            enabled: true
          k8s.deployment.available:
            enabled: true
          k8s.deployment.desired:
            enabled: true
          k8s.replicaset.available:
            enabled: true
          k8s.replicaset.desired:
            enabled: true
          k8s.daemonset.current_scheduled_nodes:
            enabled: true
          k8s.daemonset.desired_scheduled_nodes:
            enabled: true
          k8s.daemonset.misscheduled_nodes:
            enabled: true
          k8s.daemonset.ready_nodes:
            enabled: true
          k8s.statefulset.current_pods:
            enabled: true
          k8s.statefulset.desired_pods:
            enabled: true
          k8s.statefulset.ready_pods:
            enabled: true
          k8s.statefulset.updated_pods:
            enabled: true
          k8s.job.active_pods:
            enabled: true
          k8s.job.desired_successful_pods:
            enabled: true
          k8s.job.failed_pods:
            enabled: true
          k8s.job.successful_pods:
            enabled: true
          k8s.cronjob.active_jobs:
            enabled: true
          k8s.hpa.current_replicas:
            enabled: true
          k8s.hpa.desired_replicas:
            enabled: true
          k8s.hpa.max_replicas:
            enabled: true
          k8s.hpa.min_replicas:
            enabled: true
          k8s.resource_quota.hard_limit:
            enabled: true
          k8s.resource_quota.used:
            enabled: true
    
    processors:
      batch:
        timeout: 10s
        send_batch_size: 1024
      
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 15
      
      # Add cluster metadata
      resource:
        attributes:
        - key: cluster.name
          value: "k8s-cluster-demo"
          action: upsert
        - key: monitoring.source
          value: "k8s-cluster-receiver"
          action: upsert
      
      # Transform metrics for better analysis
      transform:
        metric_statements:
        - context: metric
          statements:
          # Add cluster-level aggregations
          - set(description, "Cluster-wide Kubernetes metrics from k8s_cluster receiver")
          
        - context: datapoint
          statements:
          # Add additional labels for filtering
          - set(attributes["cluster"], "k8s-cluster-demo")
    
    exporters:
      debug:
        verbosity: detailed
      
      # Example: Export to Prometheus
      # prometheus:
      #   endpoint: "0.0.0.0:8889"
      #   namespace: "k8s_cluster"
      #   resource_to_telemetry_conversion:
      #     enabled: true
      
      # Example: Export to OTLP endpoint
      # otlp:
      #   endpoint: "http://your-backend:4317"
      #   tls:
      #     insecure: true
    
    service:
      pipelines:
        metrics:
          receivers: [k8s_cluster]
          processors: [memory_limiter, resource, transform, batch]
          exporters: [debug]
```

Apply the collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for collector to be ready
kubectl wait --for=condition=available deployment/k8s-cluster-receiver-collector --timeout=300s
```

### Step 3: Create Sample Workloads for Testing

Deploy various workload types to generate metrics:

```yaml
# sample-workloads.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: k8scluster-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: app
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: sample-daemonset
  namespace: k8scluster-demo
spec:
  selector:
    matchLabels:
      app: sample-daemonset
  template:
    metadata:
      labels:
        app: sample-daemonset
    spec:
      containers:
      - name: app
        image: busybox:latest
        command: ["/bin/sh", "-c", "while true; do echo 'DaemonSet running'; sleep 30; done"]
        resources:
          requests:
            memory: "32Mi"
            cpu: "25m"
          limits:
            memory: "64Mi"
            cpu: "50m"
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: sample-statefulset
  namespace: k8scluster-demo
spec:
  serviceName: "sample-statefulset"
  replicas: 2
  selector:
    matchLabels:
      app: sample-statefulset
  template:
    metadata:
      labels:
        app: sample-statefulset
    spec:
      containers:
      - name: app
        image: busybox:latest
        command: ["/bin/sh", "-c", "while true; do echo 'StatefulSet running'; sleep 30; done"]
        resources:
          requests:
            memory: "32Mi"
            cpu: "25m"
          limits:
            memory: "64Mi"
            cpu: "50m"
---
apiVersion: batch/v1
kind: Job
metadata:
  name: sample-job
  namespace: k8scluster-demo
spec:
  template:
    spec:
      containers:
      - name: job
        image: busybox:latest
        command: ["/bin/sh", "-c", "echo 'Job completed successfully'; sleep 10"]
      restartPolicy: Never
  backoffLimit: 4
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sample-hpa
  namespace: k8scluster-demo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sample-app
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: sample-quota
  namespace: k8scluster-demo
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "10"
```

Apply sample workloads:

```bash
kubectl apply -f sample-workloads.yaml

# Wait for workloads to be ready
kubectl wait --for=condition=available deployment/sample-app --timeout=300s
```

### Step 4: Verify Metrics Collection

Check that cluster metrics are being collected:

```bash
# Check collector logs for cluster metrics
kubectl logs deployment/k8s-cluster-receiver-collector -f --tail=100

# Look for specific metric types
kubectl logs deployment/k8s-cluster-receiver-collector --tail=500 | grep -E "(k8s\.(pod|node|deployment|daemonset))"
```

### Step 5: Run Verification Script

Create and run a verification script:

```bash
# Create verification script
cat > check_cluster_metrics.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking Kubernetes Cluster receiver functionality..."

# Get collector pod name
COLLECTOR_POD=$(kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}')

if [ -z "$COLLECTOR_POD" ]; then
    echo "ERROR: No collector pod found"
    exit 1
fi

echo "Using collector pod: $COLLECTOR_POD"

# Wait for metrics to be collected
echo "Waiting for metrics collection..."
sleep 60

# Check for various metric types
echo "Checking for cluster metrics..."

METRICS_TO_CHECK=(
    "k8s.pod.phase"
    "k8s.node.condition"
    "k8s.deployment.available"
    "k8s.deployment.desired"
    "k8s.daemonset.current_scheduled_nodes"
    "k8s.statefulset.current_pods"
    "k8s.job.active_pods"
    "k8s.hpa.current_replicas"
    "k8s.resource_quota.hard_limit"
)

for metric in "${METRICS_TO_CHECK[@]}"; do
    kubectl logs $COLLECTOR_POD --tail=1000 | grep -q "$metric"
    if [ $? -eq 0 ]; then
        echo "✓ $metric metrics detected"
    else
        echo "✗ $metric metrics not found"
    fi
done

# Check for specific resource attributes
echo "Checking for resource attributes..."
kubectl logs $COLLECTOR_POD --tail=500 | grep -q "cluster.name"
if [ $? -eq 0 ]; then
    echo "✓ Cluster name attribute detected"
else
    echo "✗ Cluster name attribute not found"
fi

# Check for namespace-specific metrics
echo "Checking for namespace metrics..."
kubectl logs $COLLECTOR_POD --tail=500 | grep -q "k8scluster-demo"
if [ $? -eq 0 ]; then
    echo "✓ Namespace-specific metrics detected"
else
    echo "✗ Namespace-specific metrics not found"
fi

echo "Cluster metrics verification completed!"
EOF

chmod +x check_cluster_metrics.sh
./check_cluster_metrics.sh
```

## 🔧 Advanced Configuration

### Resource-Specific Collection

Focus on specific resource types:

```yaml
receivers:
  k8s_cluster:
    resource_attributes:
      k8s.namespace.name:
        enabled: true
      k8s.node.name:
        enabled: true
      k8s.pod.name:
        enabled: true
      k8s.deployment.name:
        enabled: true
    
    # Collect only specific metrics
    metrics:
      k8s.pod.phase:
        enabled: true
      k8s.deployment.available:
        enabled: true
      k8s.node.condition:
        enabled: true
```

### Namespace Filtering

Collect metrics from specific namespaces:

```yaml
processors:
  filter:
    metrics:
      include:
        match_type: strict
        resource_attributes:
          k8s.namespace.name: ["production", "staging"]
```

### Custom Metric Transformations

Add custom labels and transformations:

```yaml
processors:
  transform:
    metric_statements:
    - context: metric
      statements:
      - set(name, "custom_" + name) where name matches "k8s.pod.*"
      
    - context: datapoint
      statements:
      - set(attributes["environment"], "production") where resource.attributes["k8s.namespace.name"] == "prod"
      - set(attributes["team"], "platform") where resource.attributes["k8s.deployment.name"] matches ".*platform.*"
```

## 🔍 Monitoring and Analysis

### Key Metrics to Monitor

**Pod Health:**
- `k8s.pod.phase` - Pod lifecycle phases
- `k8s.pod.status_reason` - Reasons for pod status

**Deployment Status:**
- `k8s.deployment.available` - Available replicas
- `k8s.deployment.desired` - Desired replicas

**Node Health:**
- `k8s.node.condition` - Node conditions (Ready, MemoryPressure, etc.)

**Resource Usage:**
- `k8s.resource_quota.used` - Resource quota utilization
- `k8s.resource_quota.hard_limit` - Resource quota limits

### Useful Queries

When exported to Prometheus, use these queries:

```promql
# Pod restart rate
rate(k8s_pod_phase{phase="Running"}[5m])

# Unhealthy pods by namespace
k8s_pod_phase{phase!="Running"} > 0

# Deployment availability ratio
k8s_deployment_available / k8s_deployment_desired

# Node pressure conditions
k8s_node_condition{condition!="Ready", status="True"}

# Resource quota utilization
(k8s_resource_quota_used / k8s_resource_quota_hard_limit) * 100
```

## 🚨 Troubleshooting

### RBAC Issues

```bash
# Check service account permissions
kubectl auth can-i get pods --as=system:serviceaccount:k8scluster-demo:k8s-cluster-receiver

# Verify ClusterRoleBinding
kubectl describe clusterrolebinding k8s-cluster-receiver-binding

# Check for permission errors in logs
kubectl logs deployment/k8s-cluster-receiver-collector | grep -i "forbidden\|unauthorized"
```

### Missing Metrics

```bash
# Check if specific resources exist
kubectl get pods,deployments,daemonsets,statefulsets -A

# Verify receiver configuration
kubectl get opentelemetrycollector k8s-cluster-receiver -o yaml

# Check collector resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector
```

### Performance Issues

```bash
# Monitor collection interval
kubectl logs deployment/k8s-cluster-receiver-collector | grep "collection_interval"

# Check memory usage
kubectl describe pod -l app.kubernetes.io/component=opentelemetry-collector | grep -A 5 Limits

# Adjust collection interval if needed
kubectl patch opentelemetrycollector k8s-cluster-receiver --type='merge' -p='{"spec":{"config":"receivers:\n  k8s_cluster:\n    collection_interval: 60s"}}'
```

## 🔐 Security Considerations

1. **Least Privilege**: Grant minimal required permissions
2. **Namespace Isolation**: Use RBAC to limit access to specific namespaces
3. **Resource Limits**: Set appropriate CPU and memory limits
4. **Sensitive Data**: Avoid collecting sensitive information in labels

## 📊 Dashboarding and Alerting

### Dashboard Metrics

Key metrics for cluster monitoring dashboards:
- Cluster health overview (node status, pod distribution)
- Resource utilization trends
- Deployment status and availability
- Namespace resource consumption

### Alerting Rules

```yaml
# Example Prometheus alerting rules
groups:
- name: k8s-cluster-alerts
  rules:
  - alert: PodCrashLooping
    expr: k8s_pod_phase{phase="Failed"} > 0
    for: 5m
    
  - alert: DeploymentNotAvailable
    expr: k8s_deployment_available / k8s_deployment_desired < 0.8
    for: 10m
    
  - alert: NodeNotReady
    expr: k8s_node_condition{condition="Ready", status="False"} > 0
    for: 5m
```

## 📚 Related Patterns

- [kubeletstatsreceiver](../kubeletstatsreceiver/) - For detailed pod and container metrics
- [k8seventsreceiver](../k8seventsreceiver/) - For Kubernetes event monitoring
- [hostmetricsreceiver](../hostmetricsreceiver/) - For node-level system metrics

## 🧹 Cleanup

```bash
# Remove sample workloads
kubectl delete -f sample-workloads.yaml

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector k8s-cluster-receiver

# Remove RBAC
kubectl delete clusterrolebinding k8s-cluster-receiver-binding
kubectl delete clusterrole k8s-cluster-receiver-role

# Remove namespace
kubectl delete namespace k8scluster-demo
``` 