# OpenTelemetry Kubernetes Events Receiver Test

This test demonstrates the OpenTelemetry Kubernetes Events receiver configuration for collecting Kubernetes events.

## 🎯 What This Test Does

The test validates that the Kubernetes Events receiver can:
- Collect Kubernetes events from a specific namespace
- Access Kubernetes API to gather event information
- Export collected events to a debug exporter for verification

## 📋 Test Resources

### 1. Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: chainsaw-k8seventsreceiver
```

### 2. ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: chainsaw-k8seventsreceiver
  namespace: chainsaw-k8seventsreceiver
```

### 3. ClusterRole
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: chainsaw-k8seventsreceiver-role
rules:
- apiGroups:
  - ''
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
- apiGroups:
  - quota.openshift.io
  resources:
  - clusterresourcequotas
  verbs:
  - get
  - list
  - watch
```

### 4. ClusterRoleBinding
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: chainsaw-k8seventsreceiver-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: chainsaw-k8seventsreceiver-role
subjects:
  - kind: ServiceAccount
    name: chainsaw-k8seventsreceiver
    namespace: chainsaw-k8seventsreceiver
```

### 5. OpenTelemetry Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: chainsaw-k8seventsreceiver
  namespace: chainsaw-k8seventsreceiver
spec:
  mode: deployment
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: chainsaw-k8seventsreceiver
  config: |
    receivers:
      otlp:
        protocols:
          http:
      k8s_events:
        namespaces: [chainsaw-k8seventsreceiver]
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        logs:
          receivers: [k8s_events]
          exporters: [debug]
        traces:
          receivers: [otlp]
          exporters: [debug]
```

### 6. Sample Application (for event generation)
The test deploys a sample application to generate Kubernetes events that can be captured by the receiver.

## 🚀 Test Steps

1. **Create OpenTelemetry Collector** - Deploy the collector with Kubernetes Events receiver
2. **Deploy Sample Application** - Deploy an application to generate events
3. **Wait for Event Collection** - Allow 60 seconds for events to be collected
4. **Verify Event Collection** - Check that expected Kubernetes events are being collected

## 🔍 Verification

The test verification script checks for these specific event attributes:
- `k8s.event.reason` - Event reason
- `k8s.event.action` - Event action
- `k8s.event.start_time` - Event start time
- `k8s.event.name` - Event name
- `k8s.event.uid` - Event UID
- `k8s.namespace.name: Str(chainsaw-k8seventsreceiver)` - Namespace attribute
- `k8s.event.count` - Event count

## 🧹 Cleanup

The test runs in the `chainsaw-k8seventsreceiver` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses deployment mode (single instance) to collect events
- Filters events to only collect from the `chainsaw-k8seventsreceiver` namespace
- Includes both OTLP receiver for traces and k8s_events receiver for logs
- Requires RBAC permissions to access Kubernetes events and other resources
- Supports OpenShift quota resources in addition to standard Kubernetes resources 