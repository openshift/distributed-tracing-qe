# Google Managed Prometheus - Cloud Monitoring Integration

This blueprint demonstrates how to use OpenTelemetry to export metrics to Google Cloud Monitoring (formerly Stackdriver) using Google Managed Prometheus. This supports both traditional Service Account key authentication and modern Workload Identity Federation for secure, scalable metrics collection.

## 🎯 Use Case

- **Cloud-Native Monitoring**: Integrate Kubernetes metrics with Google Cloud Monitoring
- **Multi-Cloud Observability**: Centralize metrics from hybrid and multi-cloud environments
- **Compliance Integration**: Leverage Google Cloud's managed monitoring for compliance scenarios
- **Cost Optimization**: Leverage Google's managed infrastructure for metrics storage and processing
- **Security**: Implement secure authentication using Workload Identity Federation

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with Google Cloud authentication and monitoring export
- **Metrics Generators**: Kubelet stats collection and application metrics generation
- **Authentication Setup**: Either Service Account keys or Workload Identity Federation
- **Google Cloud IAM**: Proper roles and permissions for metrics writing
- **Transform Processors**: Handle Prometheus reserved attribute collision

## 🚀 Deployment Options

This blueprint provides two authentication methods:

### Option A: Service Account Key (Traditional)
- Uses JSON key files for authentication
- Simpler setup but less secure
- Suitable for development and testing

### Option B: Workload Identity Federation (Recommended)
- Uses OIDC tokens for authentication
- More secure, no long-lived credentials
- Uses secure authentication without long-lived credentials

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster  
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Google Cloud CLI (`gcloud`) installed and authenticated
- Google Cloud project with the following APIs enabled:
  - Cloud Monitoring API
  - Cloud Resource Manager API  
  - IAM Service Account Credentials API (for WIF)

### Step 1: Enable Required Google Cloud APIs

```bash
# Set your GCP project
export PROJECT_ID=$(gcloud config get-value project)

# Enable required APIs
gcloud services enable monitoring.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable iamcredentials.googleapis.com  # For Workload Identity Federation
```

### Step 2: Choose Authentication Method

## Option A: Service Account Key Authentication

### Step 2A: Create GCP Service Account and OpenShift Resources

```bash
# Create namespace
kubectl create namespace googlemanagedprometheus-demo

# Set working directory
cd googlemanagedprometheus-demo

# Create setup script
cat > gcp-sa-setup.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Configuration
PROJECT_ID=$(gcloud config get-value project)
OTEL_NAMESPACE="googlemanagedprometheus-demo"
OTEL_SA_NAME="gmp-metrics-sa"
GCP_SA_NAME="otel-gmpmetrics-sa"
SA_KEY_FILE="/tmp/gcp-sa-key.json"
SECRET_NAME="gcp-service-account-key"

echo "Setting up Google Cloud Service Account authentication..."
echo "Project: $PROJECT_ID"
echo "Namespace: $OTEL_NAMESPACE"

# Create GCP Service Account
echo "Creating GCP Service Account: $GCP_SA_NAME"
GCP_SA_EMAIL=$(gcloud iam service-accounts create "$GCP_SA_NAME" \
  --display-name="OpenTelemetry GMP Metrics Service Account" \
  --project "$PROJECT_ID" \
  --format='value(email)' \
  --quiet)

# Wait for service account to be ready
echo "Waiting for service account to be ready..."
sleep 10

# Grant required IAM roles
echo "Granting Monitoring Metric Writer role..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role="roles/monitoring.metricWriter" \
  --quiet

echo "Granting Cloud Telemetry Metrics Writer role..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role="roles/telemetry.metricsWriter" \
  --quiet

# Create and download service account key
echo "Creating service account key..."
gcloud iam service-accounts keys create "$SA_KEY_FILE" \
  --iam-account="$GCP_SA_EMAIL" \
  --project="$PROJECT_ID" \
  --quiet

# Create Kubernetes service account
echo "Creating Kubernetes service account..."
kubectl create serviceaccount "$OTEL_SA_NAME" -n "$OTEL_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create Kubernetes secret with service account key
echo "Creating Kubernetes secret with service account key..."
kubectl create secret generic "$SECRET_NAME" \
  --from-file="sa-key.json=$SA_KEY_FILE" \
  --namespace="$OTEL_NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# Clean up local key file
rm "$SA_KEY_FILE"

echo "✅ Service Account authentication setup complete!"
echo "GCP Service Account: $GCP_SA_EMAIL"
echo "Kubernetes Secret: $SECRET_NAME"
EOF

chmod +x gcp-sa-setup.sh
./gcp-sa-setup.sh
```

### Step 3A: Deploy OpenTelemetry Collector (Service Account)

```yaml
# otel-collector-sa.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gmp-metrics-role
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
  name: gmp-metrics-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: gmp-metrics-role
subjects:
- kind: ServiceAccount
  name: gmp-metrics-sa
  namespace: googlemanagedprometheus-demo

---
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: gmp
  namespace: googlemanagedprometheus-demo
spec:
  serviceAccount: gmp-metrics-sa
  
  # Mount GCP Service Account credentials
  env:
  - name: GOOGLE_APPLICATION_CREDENTIALS
    value: "/etc/google-cloud-sa/sa-key.json"
  - name: GCP_PROJECT_ID
    value: "$(PROJECT_ID)"  # Replace with your project ID
  
  volumeMounts:
  - name: google-cloud-sa-credential-configuration
    mountPath: "/etc/google-cloud-sa"
    readOnly: true
  
  volumes:
  - name: google-cloud-sa-credential-configuration
    secret:
      secretName: gcp-service-account-key
  
  config:
    receivers:
      # OTLP receiver for metrics
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 65
        spike_limit_percentage: 20
      
      # Kubernetes attributes processor
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
      
      # Set GCP-specific resource attributes
      resource/set_gcp_defaults:
        attributes:
        - action: insert
          value: "$(GCP_PROJECT_ID)"  # Replace with your project ID
          key: gcp.project_id
        - action: insert
          value: "us-central1"  # Replace with your cluster location
          key: location
        - action: insert
          value: "gmp-demo-cluster"  # Replace with your cluster name
          key: cluster
      
      # Handle Prometheus reserved attribute collision
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
      
      # Reset metric start time for cumulative metrics
      metricstarttime:
        strategy: true_reset_point
      
      # Batch processor
      batch:
        send_batch_max_size: 200
        send_batch_size: 200
        timeout: 5s
    
    exporters:
      # Google Cloud Monitoring exporter
      otlphttp:
        encoding: json
        endpoint: https://telemetry.googleapis.com
        auth:
          authenticator: googleclientauth
    
    extensions:
      # Health check extension
      health_check:
        endpoint: "0.0.0.0:13133"
      
      # Google Cloud authentication extension
      googleclientauth:
        project: "$(GCP_PROJECT_ID)"  # Replace with your project ID
    
    service:
      extensions:
      - health_check
      - googleclientauth
      
      pipelines:
        metrics/otlp:
          receivers: [otlp]
          processors:
          - k8sattributes
          - memory_limiter
          - resource/set_gcp_defaults
          - transform/collision
          - metricstarttime
          - batch
          exporters: [otlphttp]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

## Option B: Workload Identity Federation (Recommended)

### Step 2B: Set Up Workload Identity Federation

```bash
# Create namespace
kubectl create namespace googlemanagedprometheus-demo

# Create WIF setup script
cat > gcp-wif-setup.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Configuration
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
OTEL_NAMESPACE="googlemanagedprometheus-demo"
OTEL_SA_NAME="gmp-metrics-sa"
GCP_SA_NAME="otel-gmpmetrics-wif-sa"
OIDC_ISSUER=$(oc get authentication.config cluster -o jsonpath='{.spec.serviceAccountIssuer}')
POOL_ID=$(echo "$OIDC_ISSUER" | awk -F'/' '{print $NF}' | sed 's/-oidc$//')

echo "Setting up Workload Identity Federation..."
echo "Project: $PROJECT_ID ($PROJECT_NUMBER)"
echo "OIDC Issuer: $OIDC_ISSUER"
echo "Pool ID: $POOL_ID"

# Get provider ID
PROVIDER_ID=$(gcloud iam workload-identity-pools providers list \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --filter="displayName:$POOL_ID" \
  --format="value(name)" | awk -F'/' '{print $NF}')

echo "Provider ID: $PROVIDER_ID"

# Create Kubernetes service account
echo "Creating Kubernetes service account..."
kubectl create serviceaccount "$OTEL_SA_NAME" -n "$OTEL_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create GCP Service Account
echo "Creating GCP Service Account: $GCP_SA_NAME"
GCP_SA_EMAIL=$(gcloud iam service-accounts create "$GCP_SA_NAME" \
  --display-name="OpenTelemetry GMP Metrics WIF Service Account" \
  --project "$PROJECT_ID" \
  --format='value(email)' \
  --quiet)

# Wait for service account to be ready
echo "Waiting for service account to be ready..."
sleep 10

# Grant IAM roles
echo "Granting Monitoring Metric Writer role..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role="roles/monitoring.metricWriter" \
  --quiet

echo "Granting Cloud Telemetry Metrics Writer role..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role="roles/telemetry.metricsWriter" \
  --quiet

# Establish Workload Identity Federation
echo "Setting up Workload Identity Federation..."
gcloud iam service-accounts add-iam-policy-binding "$GCP_SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_ID/subject/system:serviceaccount:${OTEL_NAMESPACE}:${OTEL_SA_NAME}" \
  --project="$PROJECT_ID" \
  --quiet

# Create credential configuration
CRED_CONFIG_FILE="/tmp/credential-configuration.json"
echo "Creating WIF credential configuration..."
gcloud iam workload-identity-pools create-cred-config \
    "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_ID/providers/$PROVIDER_ID" \
    --service-account="$GCP_SA_EMAIL" \
    --credential-source-file=/var/run/secrets/otel/serviceaccount/token \
    --credential-source-type=text \
    --output-file="$CRED_CONFIG_FILE" \
    --quiet

# Create ConfigMap with credential configuration
echo "Creating ConfigMap with WIF credentials..."
kubectl create configmap gcp-wif-credentials \
  --from-file="$CRED_CONFIG_FILE" \
  --namespace="$OTEL_NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# Clean up
rm "$CRED_CONFIG_FILE"

echo "✅ Workload Identity Federation setup complete!"
echo "GCP Service Account: $GCP_SA_EMAIL"
echo "Kubernetes ConfigMap: gcp-wif-credentials"
EOF

chmod +x gcp-wif-setup.sh
./gcp-wif-setup.sh
```

### Step 3B: Deploy OpenTelemetry Collector (Workload Identity Federation)

```yaml
# otel-collector-wif.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gmp-metrics-role
rules:
- apiGroups: [""]
  resources: ["pods", "namespaces", "nodes"]
  verbs: ["get", "watch", "list"]
- apiGroups: ["apps"]
  resources: ["replicasets"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gmp-metrics-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: gmp-metrics-role
subjects:
- kind: ServiceAccount
  name: gmp-metrics-sa
  namespace: googlemanagedprometheus-demo

---
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: gmp
  namespace: googlemanagedprometheus-demo
spec:
  serviceAccount: gmp-metrics-sa
  
  # Mount WIF credential configuration
  env:
  - name: GOOGLE_APPLICATION_CREDENTIALS
    value: "/etc/workload-identity/credential-configuration.json"
  - name: GCP_PROJECT_ID
    value: "$(PROJECT_ID)"  # Replace with your project ID
  
  volumeMounts:
  - name: service-account-token-volume
    mountPath: "/var/run/secrets/otel/serviceaccount"
    readOnly: true
  - name: workload-identity-credential-configuration
    mountPath: "/etc/workload-identity"
    readOnly: true
  
  volumes:
  - name: service-account-token-volume
    projected:
      sources:
      - serviceAccountToken:
          audience: "openshift"  # Use "gcp" for GKE
          expirationSeconds: 3600
          path: token
  - name: workload-identity-credential-configuration
    configMap:
      name: gcp-wif-credentials
  
  config:
    # Same configuration as Service Account version
    # (receivers, processors, exporters, extensions, service)
    # ... (use the same config from Step 3A)
```

### Step 4: Deploy Metrics Generators

Deploy applications to generate metrics for testing:

```yaml
# metrics-generators.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: telemetrygen-metrics
  namespace: googlemanagedprometheus-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: telemetrygen-metrics
  template:
    metadata:
      labels:
        app: telemetrygen-metrics
    spec:
      containers:
      - name: metrics
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        args: 
        - "metrics"
        - "--otlp-insecure"
        - "--rate=0.5"
        - "--duration=10m"
        - "--otlp-endpoint=gmp-collector:4317"
        imagePullPolicy: IfNotPresent
        env:
        - name: OTEL_SERVICE_NAME
          value: "gmp-demo-app"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "service.name=gmp-demo-app,service.namespace=googlemanagedprometheus-demo,environment=demo"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"

---
# Kubelet Stats Collector for infrastructure metrics
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubeletstats-sa
  namespace: googlemanagedprometheus-demo

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubeletstats-role
rules:
- apiGroups: [""]
  resources: ["nodes/stats", "nodes/proxy"]
  verbs: ["get", "watch", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeletstats-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubeletstats-role
subjects:
- kind: ServiceAccount
  name: kubeletstats-sa
  namespace: googlemanagedprometheus-demo

---
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: kubeletstats
  namespace: googlemanagedprometheus-demo
spec:
  mode: daemonset
  serviceAccount: kubeletstats-sa
  
  env:
  - name: K8S_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
  
  config:
    receivers:
      kubeletstats:
        collection_interval: 30s
        auth_type: "serviceAccount"
        endpoint: "https://${env:K8S_NODE_NAME}:10250"
        insecure_skip_verify: true
        extra_metadata_labels:
        - container.id
        metric_groups:
        - container
        - pod
        - node
    
    processors:
      batch:
        timeout: 10s
        send_batch_size: 1024
    
    exporters:
      otlp:
        endpoint: gmp-collector:4317
        tls:
          insecure: true
    
    service:
      pipelines:
        metrics:
          receivers: [kubeletstats]
          processors: [batch]
          exporters: [otlp]
  
  tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

Apply the resources:

```bash
# Apply the collector configuration (choose SA or WIF version)
kubectl apply -f otel-collector-sa.yaml  # OR otel-collector-wif.yaml

# Apply metrics generators
kubectl apply -f metrics-generators.yaml

# Wait for deployments to be ready
kubectl wait --for=condition=available deployment/gmp deployment/telemetrygen-metrics --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kubeletstats --timeout=300s
```

### Step 5: Verify Metrics Export

Check that metrics are being exported to Google Cloud Monitoring:

```bash
# Check collector logs
kubectl logs -l app.kubernetes.io/name=gmp --tail=100

# Check authentication status
kubectl logs -l app.kubernetes.io/name=gmp | grep -i "auth\|gcp\|google"

# Check for successful exports
kubectl logs -l app.kubernetes.io/name=gmp | grep -i "success\|sent\|export"
```

### Step 6: View Metrics in Google Cloud Console

1. **Navigate to Cloud Monitoring**: Go to the Google Cloud Console and open Cloud Monitoring
2. **Metrics Explorer**: Navigate to Metrics Explorer
3. **Search for Metrics**: Look for metrics with the prefix:
   - `kubernetes.io/container/*` (from kubelet stats)
   - `telemetrygen_*` (from telemetrygen)
4. **Custom Dashboards**: Create dashboards to visualize your OpenTelemetry metrics

### Step 7: Query Metrics Programmatically

```bash
# Using gcloud to query metrics
gcloud monitoring metrics list --filter="metric.type=~'.*telemetrygen.*'"

# Query specific metric values
gcloud monitoring time-series list \
  --filter='metric.type="kubernetes.io/container/cpu/usage"' \
  --interval-start-time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval-end-time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

## 🔧 Advanced Configuration

### Custom Metric Transformations

Add custom processing for specific metric types:

```yaml
processors:
  transform/custom_metrics:
    metric_statements:
    - context: metric
      statements:
      # Add environment label to all metrics
      - set(resource.attributes["environment"], "production")
      
      # Rename metrics for better organization
      - set(name, "gmp." + name) where name.matches("telemetrygen_.*")
      
      # Add cost center information
      - set(resource.attributes["cost_center"], "engineering") where resource.attributes["k8s.namespace.name"] == "production"
```

### Multi-Project Export

Export metrics to multiple GCP projects:

```yaml
exporters:
  otlphttp/project1:
    endpoint: https://telemetry.googleapis.com
    headers:
      X-Goog-User-Project: "project-1"
    auth:
      authenticator: googleclientauth/project1
      
  otlphttp/project2:
    endpoint: https://telemetry.googleapis.com  
    headers:
      X-Goog-User-Project: "project-2"
    auth:
      authenticator: googleclientauth/project2

extensions:
  googleclientauth/project1:
    project: "project-1"
    
  googleclientauth/project2:
    project: "project-2"
```

### Resource Detection

Automatically detect GCP resource information:

```yaml
processors:
  resourcedetection:
    detectors: [gcp, k8snode, env]
    timeout: 2s
    override: false
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector health endpoint
kubectl port-forward svc/gmp-collector 13133:13133 &
curl http://localhost:13133

# Check Google Cloud authentication
kubectl logs -l app.kubernetes.io/name=gmp | grep -i "googleclientauth"

# Verify metrics pipeline
kubectl port-forward svc/gmp-collector 8888:8888 &
curl http://localhost:8888/metrics | grep otelcol_exporter
```

### Common Issues

**Issue: Authentication failed**
```bash
# For Service Account method
kubectl get secret gcp-service-account-key -o yaml
kubectl logs -l app.kubernetes.io/name=gmp | grep -i "credential\|auth"

# For Workload Identity Federation
kubectl get configmap gcp-wif-credentials -o yaml
kubectl describe pod -l app.kubernetes.io/name=gmp | grep -A 5 "Mounts:"
```

**Issue: Metrics not appearing in GCP**
```bash
# Check export success
kubectl logs -l app.kubernetes.io/name=gmp | grep -i "otlphttp\|export"

# Verify project configuration
kubectl get opentelemetrycollector gmp -o yaml | grep -A 5 googleclientauth

# Check API quotas
gcloud logging read "resource.type=cloud_monitoring_api AND severity>=ERROR" --limit=50
```

**Issue: Attribute collision errors**
```bash
# Check transform processor
kubectl logs -l app.kubernetes.io/name=gmp | grep -i "collision\|transform"

# Verify attribute mapping
kubectl logs -l app.kubernetes.io/name=gmp | grep -A 5 -B 5 "exported_"
```

## 📊 Cost Optimization

### Metric Filtering

Filter metrics to reduce ingestion costs:

```yaml
processors:
  filter:
    metrics:
      metric:
      # Only send critical metrics
      - name.matches("kubernetes.io/container/cpu/.*")
      - name.matches("kubernetes.io/container/memory/.*")
      - name.matches("telemetrygen_.*")
```

### Sampling Configuration

Implement metric sampling for high-volume metrics:

```yaml
processors:
  probabilistic_sampler:
    sampling_percentage: 10  # 10% sampling for non-critical metrics
```

### Batch Optimization

Optimize batching for cost efficiency:

```yaml
processors:
  batch:
    timeout: 30s
    send_batch_size: 1000
    send_batch_max_size: 2000
```

## 🔐 Security Considerations

1. **Least Privilege**: Grant minimal required IAM permissions
2. **Credential Rotation**: Regularly rotate service account keys (if using SA method)
3. **Network Security**: Use private Google Cloud endpoints when possible
4. **Audit Logging**: Enable Cloud Audit Logs for monitoring API access

## 📚 Related Patterns

- [prometheusremotewriteexporter](../prometheusremotewriteexporter/) - For Prometheus-compatible metrics
- [kubeletstatsreceiver](../kubeletstatsreceiver/) - For Kubernetes metrics collection
- [transformprocessor](../transformprocessor/) - For metrics transformation

## 🧹 Cleanup

```bash
# Remove metrics generators
kubectl delete deployment telemetrygen-metrics
kubectl delete opentelemetrycollector kubeletstats

# Remove main collector
kubectl delete opentelemetrycollector gmp

# Remove RBAC
kubectl delete clusterrolebinding gmp-metrics-binding kubeletstats-binding
kubectl delete clusterrole gmp-metrics-role kubeletstats-role

# Clean up GCP resources (Service Account method)
./gcp-sa-delete.sh

# Clean up GCP resources (WIF method)  
./gcp-wif-delete.sh

# Remove namespace
kubectl delete namespace googlemanagedprometheus-demo
```

## 📖 Additional Resources

- [Google Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [OpenTelemetry Google Cloud Exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/googlecloudexporter)
- [Google Cloud Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Google Cloud Monitoring API](https://cloud.google.com/monitoring/api/v3) 