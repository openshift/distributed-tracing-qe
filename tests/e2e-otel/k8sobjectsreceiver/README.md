# OpenTelemetry Kubernetes Objects Receiver Test

This test demonstrates the OpenTelemetry Kubernetes Objects receiver configuration for collecting Kubernetes object data.

## 🎯 What This Test Does

The test validates that the Kubernetes Objects receiver can:
- Collect Kubernetes object data using both pull and watch modes
- Access Kubernetes API to gather pod and event information
- Export collected object data to a debug exporter for verification

## 📋 Test Resources

### 1. Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: chainsaw-k8sobjectsreceiver
```

### 2. ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: chainsaw-k8sobjectsreceiver
  namespace: chainsaw-k8sobjectsreceiver
```

### 3. ClusterRole
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: chainsaw-k8sobjectsreceiver-role
rules:
- apiGroups:
  - ''
  resources:
  - events
  - pods
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - events.k8s.io
  resources:
  - events
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
  name: chainsaw-k8sobjectsreceiver-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: chainsaw-k8sobjectsreceiver-role
subjects:
  - kind: ServiceAccount
    name: chainsaw-k8sobjectsreceiver
    namespace: chainsaw-k8sobjectsreceiver
```

### 5. OpenTelemetry Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: chainsaw-k8sobjectsreceiver
  namespace: chainsaw-k8sobjectsreceiver
spec:
  mode: deployment
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: chainsaw-k8sobjectsreceiver
  config: |
    receivers:
      k8sobjects:
        objects:
          - name: pods
            mode: pull
          - name: events
            mode: watch
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        logs:
          receivers: [k8sobjects]
          exporters: [debug]
```

## 🚀 Test Steps

1. **Create OpenTelemetry Collector** - Deploy the collector with Kubernetes Objects receiver
2. **Wait for Object Collection** - Allow 10 seconds for object data to be collected
3. **Verify Object Collection** - Check that expected Kubernetes object data is being collected

## 🔍 Verification

The test verification script checks for these specific log indicators:
- `Body: Map({"object":` - Object data structure in logs
- `k8s.resource.name` - Kubernetes resource name attribute
- `event.domain` - Event domain information
- `event.name` - Event name information

## 🧹 Cleanup

The test runs in the `chainsaw-k8sobjectsreceiver` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses deployment mode (single instance) to collect object data
- Configures two object types:
  - `pods` using pull mode (periodic collection)
  - `events` using watch mode (real-time streaming)
- Requires RBAC permissions to access pods and events resources
- Supports both core API events and events.k8s.io API group events
- Outputs collected data as logs for analysis and verification 