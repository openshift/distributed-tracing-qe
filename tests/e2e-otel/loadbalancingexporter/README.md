# OpenTelemetry Load Balancing Exporter Test

This test demonstrates the OpenTelemetry Load Balancing exporter configuration for distributing traces across multiple backend collectors.

## 🎯 What This Test Does

The test validates that the Load Balancing exporter can:
- Use Kubernetes service discovery to find backend collector endpoints
- Route traces based on service name attributes for consistent routing
- Distribute traces across 5 backend collector replicas
- Ensure each service's traces go to only one backend pod (routing consistency)

## 📋 Test Resources

### 1. ServiceAccount and RBAC
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: chainsaw-lb
  namespace: chainsaw-lb

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: chainsaw-lb-role
  namespace: chainsaw-lb
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  verbs:
  - list
  - watch
  - get

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: chainsaw-lb-rolebinding
  namespace: chainsaw-lb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: chainsaw-lb-role
subjects:
- kind: ServiceAccount
  name: chainsaw-lb
  namespace: chainsaw-lb
```

### 2. Backend Collectors (5 replicas)
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: chainsaw-lb-backends
  namespace: chainsaw-lb
spec:
  replicas: 5
  config: |
    receivers:
      otlp:
        protocols:
          grpc:

    processors:

    exporters:
      debug:
        verbosity: detailed

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: []
          exporters: [debug]
```

### 3. Load Balancing Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: chainsaw-lb
  namespace: chainsaw-lb
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: chainsaw-lb
  config: |
    receivers:
      otlp:
        protocols:
          http:

    processors:

    exporters:
      loadbalancing:
        protocol:
          otlp:
            tls:
              insecure: true
        resolver:
          k8s:
            service: chainsaw-lb-backends-collector-headless.chainsaw-lb
        routing_key: "service"

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: []
          exporters: [loadbalancing]
```

### 4. Trace Generators
The test generates traces with three different service names:
- `telemetrygen-http-blue`
- `telemetrygen-http-red`
- `telemetrygen-http-green`

## 🚀 Test Steps

1. **Create Backend Collectors** - Deploy 5 replica collector backends with debug exporters
2. **Create Load Balancing Collector** - Deploy LB collector that uses K8s resolver for service discovery
3. **Generate Traces** - Send traces with different service names to the LB collector
4. **Wait for Processing** - Allow 5 seconds for traces to be distributed
5. **Check Load Balancing** - Verify each service's traces appear in only one backend pod

## 🔍 Load Balancing Configuration

### Resolver Configuration:
- **Type**: Kubernetes service discovery
- **Service**: `chainsaw-lb-backends-collector-headless.chainsaw-lb`
- **Discovery**: Uses headless service to find all backend pod IPs

### Routing Configuration:
- **Routing Key**: `"service"` - Routes based on service name attribute
- **Protocol**: OTLP with insecure TLS
- **Consistency**: Same service always routes to the same backend

### Backend Discovery:
- Automatically discovers backend endpoints using Kubernetes service resolution
- Monitors endpoint changes for dynamic backend scaling
- Requires RBAC permissions to list and watch endpoints

## 🔍 Verification

The test verification script checks that:
- All three required service names are present across the backend pods:
  - `telemetrygen-http-blue`
  - `telemetrygen-http-red` 
  - `telemetrygen-http-green`
- Each service name appears in only one backend pod (routing consistency)
- No service appears in multiple pods (proper load balancing)

Example verification output:
```bash
Service.name telemetrygen-http-blue found in pod chainsaw-lb-backends-collector-xxx
Service.name telemetrygen-http-red found in pod chainsaw-lb-backends-collector-yyy
Service.name telemetrygen-http-green found in pod chainsaw-lb-backends-collector-zzz
Success: All required service names are present and each appears in only one pod
Load balancing is working correctly!
```

## 🧹 Cleanup

The test runs in the `chainsaw-lb` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses Kubernetes service discovery for dynamic backend endpoint resolution
- Routes based on service name attribute for consistent routing per service
- Requires specific RBAC permissions for endpoint discovery
- Demonstrates horizontal scaling of trace processing across multiple collectors
- Validates routing consistency ensuring traces from the same service go to the same backend 