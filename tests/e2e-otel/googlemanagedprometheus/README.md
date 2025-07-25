# OpenTelemetry Google Managed Prometheus Exporter Test

This test demonstrates OpenTelemetry Collector configurations for exporting metrics to Google Cloud Managed Prometheus using two authentication methods.

## 🎯 What This Test Does

The test validates two authentication approaches for Google Managed Prometheus integration:
- **Service Account (SA)**: Uses Google Cloud Service Account key for authentication
- **Workload Identity Federation (WIF)**: Uses secure authentication without long-lived credentials

Both approaches demonstrate:
- Exporting OpenTelemetry metrics to Google Cloud Monitoring
- Using kubernetes attributes processor for metadata enrichment
- Avoiding attribute name collisions with Prometheus reserved names
- Processing both OTLP and Kubelet stats metrics

## 📋 Test Resources

### 1. Service Account (SA) Authentication Method

#### RBAC Configuration
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: chainsaw-gmpmetrics-role
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes"]
    verbs: ["get", "watch", "list"]
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["extensions"]
    resources: ["replicasets"]
    verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: chainsaw-gmpmetrics-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: chainsaw-gmpmetrics-role
subjects:
- kind: ServiceAccount
  name: chainsaw-gmpmetrics-sa
  namespace: chainsaw-gmpmetrics
```

#### OpenTelemetry Collector Configuration
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: gmp
  namespace: chainsaw-gmpmetrics
spec:
  serviceAccount: chainsaw-gmpmetrics-sa
  env:
    - name: GOOGLE_APPLICATION_CREDENTIALS
      value: "/etc/google-cloud-sa/sa-key.json"
  volumeMounts:
    - name: google-cloud-sa-credential-configuration
      mountPath: "/etc/google-cloud-sa"
      readOnly: true
  volumes:
    - name: google-cloud-sa-credential-configuration
      secret:
        secretName: gcp-service-account-key
  config:
    exporters:
      otlphttp:
        encoding: json
        endpoint: https://telemetry.googleapis.com
        auth:
          authenticator: googleclientauth
    extensions:
      health_check:
        endpoint: "0.0.0.0:13133"
      googleclientauth:
        project: "openshift-qe"
    processors:
      resource/set_gcp_defaults:
        attributes:
        - action: insert
          value: "openshift-qe"
          key: gcp.project_id
        - action: insert
          value: "us-central1"
          key: location
        - action: insert
          value: "ikanse-12-7lnxm"
          key: cluster
      batch:
        send_batch_max_size: 200
        send_batch_size: 200
        timeout: 5s
      k8sattributes:
        extract:
          metadata:
          - k8s.namespace.name
          - k8s.deployment.name
          - k8s.statefulset.name
          - k8s.daemonset.name
          - k8s.cronjob.name
          - k8s.job.name
          - k8s.node.name
          - k8s.pod.name
          - k8s.pod.uid
          - k8s.pod.start_time
        passthrough: false
        pod_association:
        - sources:
          - from: resource_attribute
            name: k8s.pod.ip
        - sources:
          - from: resource_attribute
            name: k8s.pod.uid
        - sources:
          - from: connection
      memory_limiter:
        check_interval: 1s
        limit_percentage: 65
        spike_limit_percentage: 20
      transform/collision:
        metric_statements:
        - context: datapoint
          statements:
          - set(attributes["exported_location"], attributes["location"])
          - delete_key(attributes, "location")
          - set(attributes["exported_cluster"], attributes["cluster"])
          - delete_key(attributes, "cluster")
          - set(attributes["exported_namespace"], attributes["namespace"])
          - delete_key(attributes, "namespace")
          - set(attributes["exported_job"], attributes["job"])
          - delete_key(attributes, "job")
          - set(attributes["exported_instance"], attributes["instance"])
          - delete_key(attributes, "instance")
          - set(attributes["exported_project_id"], attributes["project_id"])
          - delete_key(attributes, "project_id")
      metricstarttime:
          strategy: true_reset_point
    receivers:
      otlp:
        protocols:
          grpc: {}
          http: {}
    service:
      extensions:
      - health_check
      - googleclientauth
      pipelines:
        metrics/otlp:
          exporters:
          - otlphttp
          processors:
          - k8sattributes
          - memory_limiter
          - resource/set_gcp_defaults
          - transform/collision
          - metricstarttime
          - batch
          receivers:
          - otlp
```

### 2. Workload Identity Federation (WIF) Authentication Method

The WIF approach uses similar configuration but with Workload Identity Federation for enhanced security without storing service account keys.

### 3. Setup Scripts

#### Service Account Setup
- `gcp-sa-create.sh` - Creates Google Cloud Service Account and configures authentication
- `gcp-sa-delete.sh` - Cleans up Service Account resources

#### Workload Identity Federation Setup  
- `gcp-wif-create.sh` - Sets up WIF authentication
- `gcp-wif-delete.sh` - Cleans up WIF resources

### 4. Metrics Generators
Both approaches include metrics generators for testing:
- Application metrics generator
- Kubelet stats metrics collector

## 🚀 Test Steps

### Service Account Method:
1. **Create GCP Service Account** - Run setup script to create Google Cloud SA and secret
2. **Deploy OTEL Collector** - Deploy with SA authentication configuration
3. **Generate Metrics** - Create test metrics for export
4. **Verify Export** - Check metrics appear in Google Cloud Monitoring

### Workload Identity Federation Method:
1. **Setup WIF** - Configure Workload Identity Federation
2. **Deploy OTEL Collector** - Deploy with WIF authentication configuration  
3. **Generate Metrics** - Create test metrics for export
4. **Verify Export** - Check metrics appear in Google Cloud Monitoring

## 🔍 Configuration Highlights

### Authentication:
- **SA Method**: Uses mounted service account key file
- **WIF Method**: Uses secure authentication without long-lived credentials

### Processing Pipeline:
1. **k8sattributes** - Enriches metrics with Kubernetes metadata
2. **memory_limiter** - Prevents memory exhaustion  
3. **resource/set_gcp_defaults** - Adds GCP project and location information
4. **transform/collision** - Avoids Prometheus reserved attribute conflicts
5. **metricstarttime** - Handles metric reset points
6. **batch** - Optimizes export efficiency

### Collision Avoidance:
The transform processor renames attributes that conflict with Prometheus reserved names:
- `location` → `exported_location`
- `cluster` → `exported_cluster`
- `namespace` → `exported_namespace`
- `job` → `exported_job`
- `instance` → `exported_instance`
- `project_id` → `exported_project_id`

## 🧹 Cleanup

Each authentication method includes cleanup scripts to remove Google Cloud resources and Kubernetes objects.

## 📝 Key Configuration Notes

- **Two Authentication Methods**: Demonstrates both SA and WIF approaches for different security requirements
- **Collision Prevention**: Transforms attributes to avoid Prometheus reserved name conflicts
- **Kubernetes Integration**: Enriches metrics with comprehensive Kubernetes metadata
- **Resource Management**: Includes memory limiting and batch processing for efficiency
- **Security Options**: WIF method provides enhanced security without storing credentials 