# OpenTelemetry Kubernetes Cluster Receiver Test

This test demonstrates the OpenTelemetry Kubernetes Cluster receiver configuration for collecting cluster-level metrics from Kubernetes.

## 🎯 What This Test Does

The test validates that the Kubernetes Cluster receiver can:
- Collect cluster-level metrics about nodes, pods, and other Kubernetes resources
- Access Kubernetes API to gather resource information
- Export collected metrics to a debug exporter for verification

## 📋 Test Resources

### 1. ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app: opentelemetry
    component: otel-collector
  name: otel-k8s-cluster
  namespace: default
```

### 2. ClusterRole
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    app: opentelemetry
    component: otel-collector
  name: otel-k8s-cluster
rules:
- apiGroups:
  - ""
  resources:
  - events
  - namespaces
  - namespaces/status
  - nodes
  - nodes/spec
  - pods
  - pods/status
  - replicationcontrollers
  - replicationcontrollers/status
  - resourcequotas
  - services
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - apps
  resources:
  - daemonsets
  - deployments
  - replicasets
  - statefulsets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - extensions
  resources:
  - daemonsets
  - deployments
  - replicasets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - jobs
  - cronjobs
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - autoscaling
  resources:
  - horizontalpodautoscalers
  verbs:
  - get
  - list
  - watch
```

### 3. ClusterRoleBinding
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    app: opentelemetry
    component: otel-collector
  name: otel-k8s-cluster
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-k8s-cluster
subjects:
- kind: ServiceAccount
  name: otel-k8s-cluster
  namespace: default
```

### 4. OpenTelemetry Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-k8s-cluster
spec:
  serviceAccount: otel-k8s-cluster
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  config: |
    receivers:
      k8s_cluster:
        collection_interval: 10s
    processors:
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        metrics:
          receivers: [k8s_cluster]
          processors: []
          exporters: [debug]
```

## 🚀 Test Steps

1. **Create OpenTelemetry Collector** - Deploy the collector with Kubernetes Cluster receiver
2. **Wait for Metrics Collection** - Allow 60 seconds for metrics to be collected
3. **Verify Metrics Collection** - Check that expected cluster metrics are being collected

## 🔍 Verification

The test verification script checks for these specific cluster metrics:
- `k8s.node.allocatable_cpu` - Node allocatable CPU resources
- `k8s.node.allocatable_memory` - Node allocatable memory resources
- `k8s.node.condition_memory_pressure` - Node memory pressure condition
- `k8s.node.condition_ready` - Node ready condition

## 🧹 Cleanup

The test runs in the `chainsaw-k8sclusterreceiver` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses a single collector instance (not DaemonSet) to gather cluster-wide metrics
- Requires RBAC permissions to access various Kubernetes API resources
- Collects metrics every 10 seconds from the Kubernetes API
- Monitors nodes, pods, deployments, services, and other cluster resources
- Runs in the `default` namespace with cluster-wide access 