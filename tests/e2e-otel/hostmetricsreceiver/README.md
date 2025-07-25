# Host Metrics Receiver - System Resource Monitoring

This blueprint demonstrates how to use the OpenTelemetry Host Metrics receiver to collect comprehensive system-level metrics from Kubernetes nodes, including CPU, memory, disk, network, and process statistics.

## 🎯 Use Case

- **Infrastructure Monitoring**: Monitor node-level resource utilization and performance
- **Capacity Planning**: Track resource consumption trends for capacity planning
- **Performance Troubleshooting**: Identify bottlenecks and performance issues
- **Cost Optimization**: Monitor resource usage to optimize cluster costs
- **SLA Monitoring**: Track system performance against service level agreements

## 📋 What You'll Deploy

- **OpenTelemetry Collector DaemonSet**: Runs on each node to collect host metrics
- **Host Metrics Receiver**: Configured to collect CPU, memory, disk, and network metrics
- **RBAC Configuration**: Permissions for accessing node-level metrics
- **Resource Monitoring**: Comprehensive system resource visibility

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Node access permissions for DaemonSet deployment

### Step 1: Create Namespace and RBAC

```bash
# Create dedicated namespace
kubectl create namespace hostmetrics-demo

# Set as current namespace
kubectl config set-context --current --namespace=hostmetrics-demo
```

Create RBAC configuration:

```yaml
# rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hostmetrics-collector
  namespace: hostmetrics-demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: hostmetrics-collector-role
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/metrics
  - nodes/stats
  - pods
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hostmetrics-collector-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: hostmetrics-collector-role
subjects:
- kind: ServiceAccount
  name: hostmetrics-collector
  namespace: hostmetrics-demo
```

Apply RBAC configuration:

```bash
kubectl apply -f rbac.yaml
```

### Step 2: Configure Security Context Constraints (OpenShift)

For OpenShift clusters, create the necessary Security Context Constraints:

```yaml
# security-constraints.yaml (OpenShift only)
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: hostmetrics-collector-scc
allowPrivilegedContainer: false
allowHostDirVolumePlugin: true
allowHostNetwork: true
allowHostPID: true
allowHostPorts: false
allowedCapabilities:
- SYS_PTRACE
requiredDropCapabilities:
- ALL
defaultAddCapabilities: null
allowHostIPC: false
volumes:
- configMap
- downwardAPI
- emptyDir
- hostPath
- persistentVolumeClaim
- projected
- secret
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
readOnlyRootFilesystem: false
users:
- system:serviceaccount:hostmetrics-demo:hostmetrics-collector
```

Apply SCC (OpenShift only):

```bash
oc apply -f security-constraints.yaml
```

### Step 3: Deploy OpenTelemetry Collector with Host Metrics Receiver

Create the collector configuration:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: hostmetrics-collector
  namespace: hostmetrics-demo
spec:
  mode: daemonset
  serviceAccount: hostmetrics-collector
  
  config:
    receivers:
      hostmetrics:
        collection_interval: 30s
        initial_delay: 10s
        
        scrapers:
          # CPU metrics
          cpu:
            metrics:
              system.cpu.time:
                enabled: true
              system.cpu.utilization:
                enabled: true
              system.cpu.frequency:
                enabled: true
              system.cpu.physical.count:
                enabled: true
              system.cpu.logical.count:
                enabled: true
          
          # Memory metrics
          memory:
            metrics:
              system.memory.usage:
                enabled: true
              system.memory.utilization:
                enabled: true
              system.memory.limit:
                enabled: true
          
          # Disk I/O metrics
          disk:
            metrics:
              system.disk.io:
                enabled: true
              system.disk.io_time:
                enabled: true
              system.disk.operation_time:
                enabled: true
              system.disk.pending_operations:
                enabled: true
              system.disk.merged:
                enabled: true
          
          # Filesystem metrics
          filesystem:
            metrics:
              system.filesystem.usage:
                enabled: true
              system.filesystem.utilization:
                enabled: true
              system.filesystem.inodes.usage:
                enabled: true
              system.filesystem.inodes.utilization:
                enabled: true
            include_devices:
              match_type: regexp
              devices: ["^/dev/.*"]
            exclude_mount_points:
              match_type: regexp
              mount_points: ["^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/pods/.+)($|/)"]
          
          # Network metrics
          network:
            metrics:
              system.network.io:
                enabled: true
              system.network.packets:
                enabled: true
              system.network.errors:
                enabled: true
              system.network.dropped:
                enabled: true
              system.network.connections:
                enabled: true
            exclude:
              interfaces:
                match_type: regexp
                interfaces: ["^lo$", "^docker.*", "^br-.*"]
          
          # Load average metrics
          load:
            metrics:
              system.cpu.load_average.1m:
                enabled: true
              system.cpu.load_average.5m:
                enabled: true
              system.cpu.load_average.15m:
                enabled: true
          
          # Process metrics
          processes:
            metrics:
              system.processes.count:
                enabled: true
              system.processes.created:
                enabled: true
          
          # Process-specific metrics (optional, can be resource intensive)
          process:
            metrics:
              process.cpu.time:
                enabled: true
              process.cpu.utilization:
                enabled: true
              process.memory.usage:
                enabled: true
              process.memory.virtual:
                enabled: true
              process.disk.io:
                enabled: true
              process.threads:
                enabled: true
            include:
              names: [".*"]
              match_type: regexp
            exclude:
              names: ["^$"]
              match_type: regexp
    
    processors:
      batch:
        timeout: 10s
        send_batch_size: 1024
      
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 15
      
      # Add resource attributes
      resource:
        attributes:
        - key: cluster.name
          value: "hostmetrics-demo-cluster"
          action: upsert
        - key: monitoring.source
          value: "hostmetrics-receiver"
          action: upsert
        - key: host.name
          from_attribute: host.name
          action: upsert
      
      # Transform metrics for better organization
      transform:
        metric_statements:
        - context: metric
          statements:
          # Add metric descriptions
          - set(description, "Host CPU utilization percentage") where name == "system.cpu.utilization"
          - set(description, "Host memory usage in bytes") where name == "system.memory.usage"
          - set(description, "Host disk I/O operations") where name == "system.disk.io"
          - set(description, "Host network I/O bytes") where name == "system.network.io"
          
        - context: datapoint
          statements:
          # Add additional labels for filtering
          - set(attributes["environment"], "demo")
          - set(attributes["cluster"], "hostmetrics-demo-cluster")
          
          # Normalize CPU state labels
          - set(attributes["cpu_state"], attributes["state"]) where attributes["state"] != nil
          
          # Add filesystem type information
          - set(attributes["fs_type"], attributes["type"]) where attributes["type"] != nil
    
    exporters:
      debug:
        verbosity: detailed
      
      # Example: Export to Prometheus
      # prometheus:
      #   endpoint: "0.0.0.0:8889"
      #   namespace: "hostmetrics"
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
          receivers: [hostmetrics]
          processors: [memory_limiter, resource, transform, batch]
          exporters: [debug]
  
  # Host access for system metrics
  hostNetwork: true
  
  # Volume mounts for host filesystem access
  volumeMounts:
  - name: proc
    mountPath: /host/proc
    readOnly: true
  - name: sys
    mountPath: /host/sys
    readOnly: true
  - name: etc
    mountPath: /host/etc
    readOnly: true
  
  volumes:
  - name: proc
    hostPath:
      path: /proc
  - name: sys
    hostPath:
      path: /sys
  - name: etc
    hostPath:
      path: /etc
  
  # Environment variables for host metrics
  env:
  - name: HOST_PROC
    value: "/host/proc"
  - name: HOST_SYS
    value: "/host/sys"
  - name: HOST_ETC
    value: "/host/etc"
  - name: HOST_VAR
    value: "/host/var"
  - name: HOST_RUN
    value: "/host/run"
  - name: HOST_DEV
    value: "/host/dev"
  
  # Node selector and tolerations
  nodeSelector:
    kubernetes.io/os: linux
  
  tolerations:
  - operator: Exists
    effect: NoSchedule
  - operator: Exists
    effect: NoExecute
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

Apply the collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for DaemonSet to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 4: Verify Host Metrics Collection

Check that host metrics are being collected:

```bash
# Check collector pods status (should see one per node)
kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o wide

# Check collector logs for host metrics
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector -f --tail=100

# Look for specific metric types
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=500 | grep -E "(system\.(cpu|memory|disk|network))"
```

### Step 5: Run Verification Script

Create and run a verification script:

```bash
# Create verification script
cat > check_host_metrics.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking Host Metrics receiver functionality..."

# Get one collector pod name
COLLECTOR_POD=$(kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}')

if [ -z "$COLLECTOR_POD" ]; then
    echo "ERROR: No collector pod found"
    exit 1
fi

echo "Using collector pod: $COLLECTOR_POD"

# Wait for metrics to be collected
echo "Waiting for host metrics collection..."
sleep 60

# Check for various host metric types
echo "Checking for host metrics..."

METRICS_TO_CHECK=(
    "system.cpu.utilization"
    "system.memory.usage"
    "system.memory.utilization"
    "system.disk.io"
    "system.network.io"
    "system.filesystem.usage"
    "system.cpu.load_average.1m"
    "system.processes.count"
)

for metric in "${METRICS_TO_CHECK[@]}"; do
    kubectl logs $COLLECTOR_POD --tail=1000 | grep -q "$metric"
    if [ $? -eq 0 ]; then
        echo "✓ $metric metrics detected"
    else
        echo "✗ $metric metrics not found"
    fi
done

# Check for host attributes
echo "Checking for host attributes..."
kubectl logs $COLLECTOR_POD --tail=500 | grep -q "host.name"
if [ $? -eq 0 ]; then
    echo "✓ Host name attribute detected"
else
    echo "✗ Host name attribute not found"
fi

# Check DaemonSet coverage (should be running on all nodes)
TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector --field-selector=status.phase=Running --no-headers | wc -l)

echo "DaemonSet coverage: $RUNNING_PODS/$TOTAL_NODES nodes"
if [ "$RUNNING_PODS" -eq "$TOTAL_NODES" ]; then
    echo "✓ DaemonSet running on all nodes"
else
    echo "✗ DaemonSet not running on all nodes"
fi

echo "Host metrics verification completed!"
EOF

chmod +x check_host_metrics.sh
./check_host_metrics.sh
```

## 🔧 Advanced Configuration

### Selective Metric Collection

For resource-constrained environments, collect only essential metrics:

```yaml
receivers:
  hostmetrics:
    collection_interval: 60s
    scrapers:
      cpu:
        metrics:
          system.cpu.utilization:
            enabled: true
      memory:
        metrics:
          system.memory.utilization:
            enabled: true
      disk:
        metrics:
          system.disk.io:
            enabled: true
      network:
        metrics:
          system.network.io:
            enabled: true
```

### High-Frequency Monitoring

For detailed monitoring with higher resolution:

```yaml
receivers:
  hostmetrics:
    collection_interval: 10s
    scrapers:
      cpu:
        metrics:
          system.cpu.utilization:
            enabled: true
      memory:
        metrics:
          system.memory.usage:
            enabled: true
          system.memory.utilization:
            enabled: true
```

### Process-Specific Monitoring

Monitor specific processes:

```yaml
receivers:
  hostmetrics:
    scrapers:
      process:
        include:
          names: ["kubelet", "containerd", "dockerd", "kube-proxy"]
          match_type: strict
        metrics:
          process.cpu.utilization:
            enabled: true
          process.memory.usage:
            enabled: true
```

### Custom Filesystem Filtering

Monitor specific filesystems:

```yaml
receivers:
  hostmetrics:
    scrapers:
      filesystem:
        include_devices:
          match_type: regexp
          devices: ["^/dev/(nvme|sd|xvd).*"]
        exclude_mount_points:
          match_type: regexp
          mount_points: ["^/(dev|proc|sys|run)"]
        include_virtual_fs: false
```

## 🔍 Monitoring and Analysis

### Key Metrics to Monitor

**CPU Metrics:**
- `system.cpu.utilization` - CPU usage percentage by state
- `system.cpu.load_average.1m` - 1-minute load average

**Memory Metrics:**
- `system.memory.utilization` - Memory usage percentage
- `system.memory.usage` - Memory usage by state (used, free, cached)

**Disk Metrics:**
- `system.disk.io` - Disk read/write operations
- `system.filesystem.utilization` - Filesystem usage percentage

**Network Metrics:**
- `system.network.io` - Network bytes sent/received
- `system.network.packets` - Network packets sent/received

### Useful Queries

When exported to Prometheus, use these queries:

```promql
# Average CPU utilization across cluster
avg(system_cpu_utilization{state="used"}) by (cluster)

# Memory utilization by node
system_memory_utilization by (host_name)

# Disk I/O rate
rate(system_disk_io[5m])

# Network throughput
rate(system_network_io[5m])

# Filesystem usage above threshold
system_filesystem_utilization > 0.8

# Load average trend
system_cpu_load_average_1m
```

## 🚨 Troubleshooting

### Permission Issues

```bash
# Check DaemonSet pods status
kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector

# Check for permission errors in logs
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "permission\|denied\|forbidden"

# Verify host path mounts
kubectl describe pod -l app.kubernetes.io/component=opentelemetry-collector | grep -A 10 "Mounts:"
```

### Missing Metrics

```bash
# Check if host paths are accessible
kubectl exec deployment/hostmetrics-collector-collector -- ls -la /host/proc/

# Verify scraper configuration
kubectl get opentelemetrycollector hostmetrics-collector -o yaml | grep -A 20 "scrapers:"

# Check resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector
```

### Performance Issues

```bash
# Monitor collection interval
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "collection_interval"

# Check memory usage
kubectl describe pod -l app.kubernetes.io/component=opentelemetry-collector | grep -A 5 Limits

# Reduce collection frequency if needed
kubectl patch opentelemetrycollector hostmetrics-collector --type='merge' -p='{"spec":{"config":"receivers:\n  hostmetrics:\n    collection_interval: 60s"}}'
```

### Node Coverage Issues

```bash
# Check DaemonSet status
kubectl get daemonset -l app.kubernetes.io/component=opentelemetry-collector

# Check node selectors and tolerations
kubectl describe daemonset -l app.kubernetes.io/component=opentelemetry-collector

# Check for node taints
kubectl describe nodes | grep -A 5 Taints
```

## 🔐 Security Considerations

1. **Host Access**: Minimize host path access to required directories only
2. **Service Account**: Use dedicated service account with minimal permissions
3. **Security Context**: Run with non-root user when possible
4. **Network Access**: Use host network only when necessary
5. **Resource Limits**: Set appropriate CPU and memory limits

## 📊 Performance Optimization

### Resource Management

```yaml
spec:
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

### Collection Optimization

```yaml
receivers:
  hostmetrics:
    collection_interval: 30s  # Balance between resolution and overhead
    scrapers:
      cpu:
        metrics:
          system.cpu.time:
            enabled: false  # Disable high-cardinality metrics if not needed
```

## 📚 Related Patterns

- [k8sclusterreceiver](../k8sclusterreceiver/) - For Kubernetes cluster metrics
- [kubeletstatsreceiver](../kubeletstatsreceiver/) - For container-level metrics
- [prometheusremotewriteexporter](../prometheusremotewriteexporter/) - For metrics export

## 🧹 Cleanup

```bash
# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector hostmetrics-collector

# Remove RBAC
kubectl delete clusterrolebinding hostmetrics-collector-binding
kubectl delete clusterrole hostmetrics-collector-role
kubectl delete serviceaccount hostmetrics-collector

# Remove security context constraints (OpenShift)
oc delete securitycontextconstraints hostmetrics-collector-scc

# Remove namespace
kubectl delete namespace hostmetrics-demo
``` 