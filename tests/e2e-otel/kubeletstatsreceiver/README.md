# Kubelet Stats Receiver - Container and Node Metrics

This blueprint demonstrates how to use the OpenTelemetry Kubelet Stats Receiver to collect detailed container and node metrics directly from the kubelet API. This is essential for monitoring resource utilization, performance analysis, and capacity planning.

## 🎯 Use Case

- **Resource Monitoring**: Track CPU, memory, and filesystem usage for containers and nodes
- **Performance Analysis**: Monitor container performance metrics and resource consumption
- **Capacity Planning**: Understand resource utilization patterns for scaling decisions
- **Cost Optimization**: Identify over/under-provisioned resources
- **SLA Monitoring**: Ensure containers stay within resource limits

## 📋 What You'll Deploy

- **OpenTelemetry Collector DaemonSet**: Runs on each node to collect kubelet metrics
- **Service Account & RBAC**: Permissions to access kubelet stats API
- **Kubelet Stats Receiver**: Configured to collect container and node metrics
- **Node Environment Variable**: Dynamic node name injection for kubelet endpoint

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Kubelet stats API enabled (usually enabled by default)

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace kubeletstatsreceiver-demo

# Set as current namespace
kubectl config set-context --current --namespace=kubeletstatsreceiver-demo
```

### Step 2: Create Service Account and RBAC

Create the necessary permissions for accessing kubelet stats:

```yaml
# rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubeletstatsreceiver-sa
  namespace: kubeletstatsreceiver-demo

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubeletstatsreceiver-role
rules:
# Access to kubelet stats API
- apiGroups: [""]
  resources: ["nodes/stats"]
  verbs: ["get", "watch", "list"]

# Access to kubelet proxy API
- apiGroups: [""]
  resources: ["nodes/proxy"]
  verbs: ["get"]

# Optional: Access to nodes for metadata
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]

# Optional: Access to pods for context
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeletstatsreceiver-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubeletstatsreceiver-role
subjects:
- kind: ServiceAccount
  name: kubeletstatsreceiver-sa
  namespace: kubeletstatsreceiver-demo
```

Apply the RBAC configuration:

```bash
kubectl apply -f rbac.yaml
```

### Step 3: Deploy OpenTelemetry Collector with Kubelet Stats Receiver

Create the collector configuration:

```yaml
# otel-kubeletstatsreceiver.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: kubeletstatsreceiver
  namespace: kubeletstatsreceiver-demo
spec:
  mode: daemonset
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: kubeletstatsreceiver-sa
  
  # Environment variables for dynamic configuration
  env:
  - name: K8S_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
  - name: K8S_NODE_IP
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
  
  config:
    receivers:
      # Kubelet stats receiver configuration
      kubeletstats:
        # Collection interval
        collection_interval: 10s
        
        # Authentication method
        auth_type: "serviceAccount"
        
        # Kubelet endpoint (dynamic based on node)
        endpoint: "https://${env:K8S_NODE_NAME}:10250"
        
        # TLS configuration
        insecure_skip_verify: true
        
        # Additional metadata labels to include
        extra_metadata_labels:
          - container.id
          - k8s.volume.type
          - k8s.cluster.name
        
        # Metric groups to collect
        metric_groups:
          - container
          - pod
          - node
          - volume
        
        # Optional: Kubernetes API configuration for additional metadata
        k8s_api_config:
          auth_type: serviceAccount
    
    processors:
      # Batch processor for efficiency
      batch:
        timeout: 30s
        send_batch_size: 1024
        send_batch_max_size: 2048
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 15
      
      # Resource processor to add metadata
      resource:
        attributes:
        - key: cluster.name
          value: "kubeletstats-demo-cluster"
          action: upsert
        - key: node.name
          from_attribute: "k8s.node.name"
          action: upsert
        - key: metrics.source
          value: "kubelet-stats"
          action: upsert
      
      # Transform processor for metric enhancement
      transform:
        metric_statements:
        - context: metric
          statements:
          # Add cluster region
          - set(resource.attributes["cluster.region"], "us-east-1")
          
          # Normalize container names
          - set(resource.attributes["service.name"], resource.attributes["k8s.pod.name"]) where resource.attributes["k8s.pod.name"] != nil
          
          # Add cost center based on namespace
          - set(resource.attributes["cost.center"], "production") where resource.attributes["k8s.namespace.name"] == "default"
          - set(resource.attributes["cost.center"], "development") where resource.attributes["k8s.namespace.name"] != "default"
    
    exporters:
      # Debug exporter for troubleshooting
      debug:
        verbosity: detailed
        
      # Optional: Prometheus exporter
      # prometheus:
      #   endpoint: "0.0.0.0:8889"
      #   resource_to_telemetry_conversion:
      #     enabled: true
      
      # Optional: OTLP exporter to external system
      # otlp:
      #   endpoint: "http://central-metrics-collector:4317"
      #   insecure: true
    
    service:
      pipelines:
        metrics:
          receivers: [kubeletstats]
          processors: [memory_limiter, resource, transform, batch]
          exporters: [debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
  
  # Tolerations to run on all nodes including control plane
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
  
  # Node selector (optional)
  nodeSelector:
    kubernetes.io/os: linux
  
  # Resource limits
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
```

Apply the collector:

```bash
kubectl apply -f otel-kubeletstatsreceiver.yaml

# Wait for the DaemonSet to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 4: Verify Metric Collection

Check that kubelet metrics are being collected:

```bash
# Check DaemonSet status
kubectl get daemonset -l app.kubernetes.io/component=opentelemetry-collector

# Check pod distribution across nodes
kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o wide

# Check collector logs for metrics
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=100
```

### Step 5: Generate Some Load

Create workloads to generate meaningful metrics:

```bash
# Deploy a CPU-intensive workload
kubectl run cpu-load --image=busybox --restart=Never -- sh -c "while true; do dd if=/dev/zero of=/dev/null bs=1M count=1000; done"

# Deploy a memory-intensive workload
kubectl run memory-load --image=busybox --restart=Never -- sh -c "while true; do head -c 100M </dev/urandom | tail; done"

# Wait a bit for metrics to be collected
sleep 60

# Check if workloads are running
kubectl get pods
```

### Step 6: Run Verification Script

Create an automated verification script:

```bash
# Create verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking kubelet stats receiver functionality..."

# Define the label selector and namespace
LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=${NAMESPACE:-kubeletstatsreceiver-demo}

# Define the expected kubelet metrics
EXPECTED_METRICS=(
  "container.cpu.time"
  "container.cpu.usage"
  "container.filesystem.available"
  "container.filesystem.capacity"
  "container.filesystem.usage"
  "container.memory.major_page_faults"
  "container.memory.page_faults"
  "container.memory.rss"
  "container.memory.usage"
  "container.memory.working_set"
  "k8s.node.cpu.time"
  "k8s.node.cpu.usage"
  "k8s.node.filesystem.available"
  "k8s.node.filesystem.capacity"
  "k8s.node.filesystem.usage"
  "k8s.node.memory.available"
  "k8s.node.memory.major_page_faults"
  "k8s.node.memory.page_faults"
  "k8s.node.memory.rss"
  "k8s.node.memory.usage"
  "k8s.node.memory.working_set"
  "k8s.pod.cpu.time"
  "k8s.pod.cpu.usage"
  "k8s.pod.filesystem.available"
  "k8s.pod.filesystem.capacity"
  "k8s.pod.filesystem.usage"
  "k8s.pod.memory.major_page_faults"
  "k8s.pod.memory.page_faults"
  "k8s.pod.memory.rss"
  "k8s.pod.memory.usage"
  "k8s.pod.memory.working_set"
  "k8s.pod.network.errors"
  "k8s.pod.network.io"
)

# Get the collector pods
PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "❌ No collector pods found with label $LABEL_SELECTOR in namespace $NAMESPACE"
    exit 1
fi

echo "Found ${#PODS[@]} collector pod(s): ${PODS[*]}"

# Check first pod for metrics (should be consistent across all pods)
POD=${PODS[0]}
echo "Checking pod: $POD"

# Get logs from the pod
LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=500 2>/dev/null || echo "")

if [ -z "$LOGS" ]; then
    echo "❌ No logs found in pod $POD"
    exit 1
fi

# Track found metrics
found_metrics=0
missing_metrics=()

echo "Searching for kubelet metrics..."

# Check for each expected metric
for METRIC in "${EXPECTED_METRICS[@]}"; do
    if echo "$LOGS" | grep -q -- "$METRIC"; then
        echo "✅ \"$METRIC\" found in $POD"
        ((found_metrics++))
    else
        echo "⚠️  \"$METRIC\" not found in $POD"
        missing_metrics+=("$METRIC")
    fi
done

# Evaluate results
total_metrics=${#EXPECTED_METRICS[@]}
success_threshold=$((total_metrics * 70 / 100))  # 70% success rate

echo ""
echo "Metrics verification summary:"
echo "Found: $found_metrics/$total_metrics metrics"

if [ $found_metrics -ge $success_threshold ]; then
    echo "🎉 Kubelet stats receiver verification completed successfully!"
    echo "✅ Sufficient metrics found ($found_metrics/$total_metrics)"
    if [ ${#missing_metrics[@]} -gt 0 ]; then
        echo "⚠️  Missing metrics (may be environment-specific): ${missing_metrics[*]:0:5}..."
    fi
else
    echo "❌ Kubelet stats receiver verification failed"
    echo "❌ Insufficient metrics found ($found_metrics/$total_metrics, needed: $success_threshold)"
    echo "Missing metrics: ${missing_metrics[*]:0:10}..."
    exit 1
fi
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Custom Collection Intervals

Configure different collection intervals for different metric types:

```yaml
receivers:
  kubeletstats/frequent:
    collection_interval: 5s
    metric_groups: [container, pod]
  
  kubeletstats/infrequent:
    collection_interval: 60s
    metric_groups: [node, volume]
```

### Selective Metric Collection

Collect only specific metrics:

```yaml
receivers:
  kubeletstats:
    metric_groups:
      - container
      - pod
    metrics:
      container.cpu.usage:
        enabled: true
      container.memory.usage:
        enabled: true
      container.filesystem.usage:
        enabled: false
```

### Enhanced Metadata

Add additional labels and metadata:

```yaml
receivers:
  kubeletstats:
    extra_metadata_labels:
      - container.image.name
      - container.image.tag
      - k8s.pod.qos_class
      - k8s.container.restart_count
```

### Multi-Cluster Configuration

Configure for multiple clusters:

```yaml
processors:
  resource/cluster:
    attributes:
    - key: cluster.name
      value: "${env:CLUSTER_NAME}"
      action: upsert
    - key: cluster.environment
      value: "${env:CLUSTER_ENV}"
      action: upsert
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check DaemonSet status
kubectl get daemonset -l app.kubernetes.io/component=opentelemetry-collector

# Check kubelet connectivity
kubectl get --raw "/api/v1/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')/proxy/stats/summary"

# Check resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector
```

### Common Issues

**Issue: Authentication errors**
```bash
# Check service account permissions
kubectl auth can-i get nodes/stats --as=system:serviceaccount:kubeletstatsreceiver-demo:kubeletstatsreceiver-sa

# Verify RBAC binding
kubectl describe clusterrolebinding kubeletstatsreceiver-binding
```

**Issue: Kubelet connection failed**
```bash
# Check kubelet status on nodes
kubectl get nodes
kubectl describe node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# Test kubelet endpoint directly
kubectl get --raw "/api/v1/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')/proxy/stats"
```

**Issue: Missing metrics**
```bash
# Check collector configuration
kubectl get opentelemetrycollector kubeletstatsreceiver -o yaml | grep -A 20 kubeletstats

# Check collector logs for errors
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i error
```

**Issue: High resource usage**
```bash
# Check collector resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Adjust collection interval
kubectl patch opentelemetrycollector kubeletstatsreceiver --type='merge' -p='{"spec":{"config":"receivers:\n  kubeletstats:\n    collection_interval: 30s"}}'
```

### Kubelet API Diagnostics

```bash
# Check kubelet health
kubectl get --raw "/api/v1/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')/proxy/healthz"

# Get kubelet version
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'

# Check kubelet configuration
kubectl get --raw "/api/v1/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')/proxy/configz"
```

## 📊 Metric Categories

### Container Metrics

- **CPU**: `container.cpu.time`, `container.cpu.usage`
- **Memory**: `container.memory.usage`, `container.memory.working_set`, `container.memory.rss`
- **Filesystem**: `container.filesystem.usage`, `container.filesystem.available`
- **Network**: Network I/O and error statistics

### Pod Metrics

- **CPU**: `k8s.pod.cpu.time`, `k8s.pod.cpu.usage`
- **Memory**: `k8s.pod.memory.usage`, `k8s.pod.memory.working_set`
- **Network**: `k8s.pod.network.io`, `k8s.pod.network.errors`
- **Filesystem**: `k8s.pod.filesystem.usage`, `k8s.pod.filesystem.available`

### Node Metrics

- **CPU**: `k8s.node.cpu.time`, `k8s.node.cpu.usage`
- **Memory**: `k8s.node.memory.usage`, `k8s.node.memory.available`
- **Filesystem**: `k8s.node.filesystem.usage`, `k8s.node.filesystem.available`
- **Network**: Node-level network statistics

### Volume Metrics

- **Usage**: Volume usage and capacity metrics
- **Availability**: Available space on volumes
- **IOPS**: Input/output operations (if available)

## 🔐 Security Considerations

1. **RBAC Permissions**: Grant minimal required permissions for kubelet access
2. **TLS Configuration**: Configure TLS validation as needed
3. **Node Access**: Restrict which nodes can be accessed
4. **Resource Limits**: Set appropriate limits to prevent resource exhaustion

## 📚 Related Patterns

- [hostmetricsreceiver](../hostmetricsreceiver/) - For OS-level metrics
- [k8sclusterreceiver](../k8sclusterreceiver/) - For cluster-wide metrics
- [k8seventsreceiver](../k8seventsreceiver/) - For cluster events

## 🧹 Cleanup

```bash
# Remove test workloads
kubectl delete pod cpu-load memory-load --ignore-not-found=true

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector kubeletstatsreceiver

# Remove RBAC configuration
kubectl delete clusterrolebinding kubeletstatsreceiver-binding
kubectl delete clusterrole kubeletstatsreceiver-role
kubectl delete serviceaccount kubeletstatsreceiver-sa

# Remove namespace
kubectl delete namespace kubeletstatsreceiver-demo
```

## 📖 Additional Resources

- [OpenTelemetry Kubelet Stats Receiver Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/kubeletstatsreceiver)
- [Kubernetes Kubelet API](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)
- [Kubernetes Resource Monitoring](https://kubernetes.io/docs/concepts/cluster-administration/resource-usage-monitoring/) 