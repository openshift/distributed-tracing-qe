# OpenTelemetry Group By Attributes Processor Test

This test demonstrates the OpenTelemetry Group By Attributes processor configuration for grouping metrics by specific attributes.

## 🎯 What This Test Does

The test validates a metric processing pipeline that:
- Collects Kubelet stats metrics using DaemonSet collectors
- Forwards metrics to a main collector with Group By Attributes processor
- Groups metrics to reduce cardinality and improve metric organization
- Exports processed metrics to Prometheus for monitoring

## 📋 Test Resources

### 1. User Workload Monitoring Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```

### 2. ServiceAccount and RBAC
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: chainsaw-gba
  namespace: chainsaw-gba

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: chainsaw-gba-role
rules:
  - apiGroups: ['']
    resources: ['nodes/stats']
    verbs: ['get', 'watch', 'list']
  - apiGroups: [""]
    resources: ["nodes/proxy"]
    verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: chainsaw-gba-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: chainsaw-gba-role
subjects:
  - kind: ServiceAccount
    name: chainsaw-gba
    namespace: chainsaw-gba
```

### 3. Kubelet Stats Collector (DaemonSet)
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: chainsaw-gba
  namespace: chainsaw-gba
spec:
  mode: daemonset
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: chainsaw-gba
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
    exporters:
      otlp:
        endpoint: gba-main-collector.chainsaw-gba.svc:4317
        tls:
          insecure: true
    service:
      pipelines:
        metrics:
          receivers: [kubeletstats]
          exporters: [otlp]
  tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
```

### 4. Main Collector with Group By Attributes Processor
The test includes a main collector that receives metrics from the DaemonSet collectors and applies the Group By Attributes processor to organize and reduce metric cardinality.

### 5. Monitoring View Role
The test creates appropriate RBAC permissions to access metrics endpoints for verification.

## 🚀 Test Steps

1. **Enable User Workload Monitoring** - Configure OpenShift cluster monitoring
2. **Create Kubelet Stats Collector** - Deploy DaemonSet to collect node metrics
3. **Create Main Collector with Group By Attributes** - Deploy central collector for processing
4. **Check Metrics** - Create monitoring role and verify grouped metrics

## 🔍 Verification

The test verification checks that:
- Kubelet stats metrics are successfully collected from all nodes
- Metrics are forwarded to the main collector
- Group By Attributes processor successfully groups metrics
- Processed metrics are available via Prometheus endpoint
- Metric cardinality is appropriately reduced through grouping

## 🧹 Cleanup

The test runs in the `chainsaw-gba` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses DaemonSet mode for comprehensive node metric collection
- Integrates with OpenShift user workload monitoring
- Demonstrates metric forwarding between collectors
- Group By Attributes processor reduces metric cardinality
- Requires service account authentication for kubelet access
- Tolerates master node taints for complete coverage
- Enables Prometheus integration for metric monitoring 