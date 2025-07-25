# OpenTelemetry Kubelet Stats Receiver Test

This test demonstrates the OpenTelemetry Kubelet Stats receiver configuration for collecting container and pod metrics from Kubernetes nodes.

## 🎯 What This Test Does

The test validates that the Kubelet Stats receiver can:
- Collect container, pod, and node metrics from kubelet stats API
- Access kubelet metrics endpoint securely using service account authentication
- Export collected metrics to a debug exporter for verification

## 📋 Test Resources

### 1. Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: chainsaw-kubeletstatsreceiver
```

### 2. ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: chainsaw-kubeletstatsreceiver
  namespace: chainsaw-kubeletstatsreceiver
```

### 3. ClusterRole
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: chainsaw-kubeletstatsreceiver-role
rules:
  - apiGroups: ['']
    resources: ['nodes/stats']
    verbs: ['get', 'watch', 'list']
  - apiGroups: [""]
    resources: ["nodes/proxy"]
    verbs: ["get"]
```

### 4. ClusterRoleBinding
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: chainsaw-kubeletstatsreceiver-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: chainsaw-kubeletstatsreceiver-role
subjects:
  - kind: ServiceAccount
    name: chainsaw-kubeletstatsreceiver
    namespace: chainsaw-kubeletstatsreceiver
```

### 5. OpenTelemetry Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: chainsaw-kubeletstatsreceiver
  namespace: chainsaw-kubeletstatsreceiver
spec:
  mode: daemonset
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: chainsaw-kubeletstatsreceiver
  env:
  - name: K8S_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
  config: |
    receivers:
      kubeletstats:
        collection_interval: 20s
        auth_type: "serviceAccount"
        endpoint: "https://${env:K8S_NODE_NAME}:10250"
        insecure_skip_verify: true
        extra_metadata_labels:
          - container.id
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        metrics:
          receivers: [kubeletstats]
          exporters: [debug]
  tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
```

## 🚀 Test Steps

1. **Create OpenTelemetry Collector** - Deploy the collector with Kubelet Stats receiver
2. **Wait for Metrics Collection** - Allow 60 seconds for metrics to be collected
3. **Verify Metrics Collection** - Check that expected container and pod metrics are being collected

## 🔍 Verification

The test verification script checks for these specific metrics:

**Container Metrics:**
- `container.cpu.time` - Container CPU time
- `container.cpu.usage` - Container CPU usage
- `container.filesystem.available` - Container filesystem available space
- `container.filesystem.capacity` - Container filesystem capacity
- `container.filesystem.usage` - Container filesystem usage
- `container.memory.major_page_faults` - Container memory major page faults
- `container.memory.page_faults` - Container memory page faults
- `container.memory.rss` - Container memory RSS
- `container.memory.usage` - Container memory usage
- `container.memory.working_set` - Container memory working set

**Node Metrics:**
- `k8s.node.cpu.time` - Node CPU time
- `k8s.node.cpu.usage` - Node CPU usage
- `k8s.node.filesystem.available` - Node filesystem available space
- `k8s.node.filesystem.capacity` - Node filesystem capacity
- `k8s.node.filesystem.usage` - Node filesystem usage
- `k8s.node.memory.available` - Node memory available
- `k8s.node.memory.major_page_faults` - Node memory major page faults
- `k8s.node.memory.page_faults` - Node memory page faults
- `k8s.node.memory.rss` - Node memory RSS
- `k8s.node.memory.usage` - Node memory usage
- `k8s.node.memory.working_set` - Node memory working set

**Pod Metrics:**
- `k8s.pod.cpu.time` - Pod CPU time
- `k8s.pod.cpu.usage` - Pod CPU usage
- `k8s.pod.filesystem.available` - Pod filesystem available space
- `k8s.pod.filesystem.capacity` - Pod filesystem capacity
- `k8s.pod.filesystem.usage` - Pod filesystem usage
- `k8s.pod.memory.major_page_faults` - Pod memory major page faults
- `k8s.pod.memory.page_faults` - Pod memory page faults
- `k8s.pod.memory.rss` - Pod memory RSS
- `k8s.pod.memory.usage` - Pod memory usage
- `k8s.pod.memory.working_set` - Pod memory working set
- `k8s.pod.network.errors` - Pod network errors
- `k8s.pod.network.io` - Pod network I/O

## 🧹 Cleanup

The test runs in the `chainsaw-kubeletstatsreceiver` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses DaemonSet mode to collect metrics from all nodes
- Connects to kubelet stats API on port 10250 using HTTPS
- Uses service account authentication for secure access
- Skips TLS verification for testing purposes
- Collects metrics every 20 seconds
- Includes container.id as extra metadata label
- Tolerates master node taints for comprehensive coverage 