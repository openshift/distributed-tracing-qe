# Kubernetes Events Receiver - Cluster Event Collection

This blueprint demonstrates how to use the OpenTelemetry Kubernetes Events Receiver to collect cluster events from the Kubernetes API. This is essential for monitoring cluster state changes, troubleshooting deployment issues, and understanding the lifecycle of Kubernetes resources.

## 🎯 Use Case

- **Cluster Monitoring**: Track Kubernetes cluster events and state changes
- **Troubleshooting**: Debug pod scheduling, deployment failures, and resource issues
- **Audit Trail**: Maintain a record of cluster activities for compliance
- **Alerting**: Set up alerts based on critical cluster events
- **Operational Insights**: Understand resource lifecycle and cluster behavior

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with Kubernetes events receiver
- **Service Account & RBAC**: Permissions to read cluster events and resources
- **Sample Application**: HotROD app to generate Kubernetes events
- **Event Collection**: Automated collection of cluster events as logs

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Cluster admin permissions (for RBAC setup)

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace k8seventsreceiver-demo

# Set as current namespace
kubectl config set-context --current --namespace=k8seventsreceiver-demo
```

### Step 2: Create Service Account and RBAC

Create the necessary permissions for accessing Kubernetes events and resources:

```yaml
# rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k8seventsreceiver-sa
  namespace: k8seventsreceiver-demo

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8seventsreceiver-role
rules:
# Core resources for event context
- apiGroups: [""]
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

# Apps API group
- apiGroups: ["apps"]
  resources:
  - daemonsets
  - deployments
  - replicasets
  - statefulsets
  verbs:
  - get
  - list
  - watch

# Extensions API group (legacy)
- apiGroups: ["extensions"]
  resources:
  - daemonsets
  - deployments
  - replicasets
  verbs:
  - get
  - list
  - watch

# Batch API group
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs:
  - get
  - list
  - watch

# Autoscaling
- apiGroups: ["autoscaling"]
  resources:
  - horizontalpodautoscalers
  verbs:
  - get
  - list
  - watch

# OpenShift specific (optional)
- apiGroups: ["quota.openshift.io"]
  resources:
  - clusterresourcequotas
  verbs:
  - get
  - list
  - watch

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: k8seventsreceiver-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8seventsreceiver-role
subjects:
- kind: ServiceAccount
  name: k8seventsreceiver-sa
  namespace: k8seventsreceiver-demo
```

Apply the RBAC configuration:

```bash
kubectl apply -f rbac.yaml
```

### Step 3: Deploy OpenTelemetry Collector with Kubernetes Events Receiver

Create the collector configuration:

```yaml
# otel-k8seventsreceiver.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: k8seventsreceiver
  namespace: k8seventsreceiver-demo
spec:
  mode: deployment
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: k8seventsreceiver-sa
  
  config:
    receivers:
      # OTLP receiver for application traces/metrics
      otlp:
        protocols:
          http:
            endpoint: 0.0.0.0:4318
          grpc:
            endpoint: 0.0.0.0:4317
      
      # Kubernetes events receiver
      k8s_events:
        # Collect events from specific namespaces (optional)
        namespaces: [k8seventsreceiver-demo, default, kube-system]
        
        # Optional: Configure startup mode
        # startup_mode: watch  # Options: watch, replay, replay-and-watch
    
    processors:
      # Batch processor for efficiency
      batch:
        timeout: 5s
        send_batch_size: 1024
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
      
      # Resource processor to add metadata
      resource:
        attributes:
        - key: cluster.name
          value: "k8sevents-demo-cluster"
          action: upsert
        - key: log.source
          value: "kubernetes-events"
          action: upsert
      
      # Transform processor to enrich events
      transform:
        log_statements:
        - context: log
          statements:
          # Extract event severity from type
          - set(attributes["event.severity"], "info") where attributes["k8s.event.type"] == "Normal"
          - set(attributes["event.severity"], "warning") where attributes["k8s.event.type"] == "Warning"
          
          # Set log level based on event type
          - set(severity_text, "INFO") where attributes["k8s.event.type"] == "Normal"
          - set(severity_text, "WARN") where attributes["k8s.event.type"] == "Warning"
          
          # Add resource type from involved object
          - set(attributes["k8s.resource.kind"], attributes["k8s.event.involved_object.kind"]) where attributes["k8s.event.involved_object.kind"] != nil
          - set(attributes["k8s.resource.name"], attributes["k8s.event.involved_object.name"]) where attributes["k8s.event.involved_object.name"] != nil
          
          # Create a structured message
          - set(body, Concat([attributes["k8s.event.reason"], ": ", body], ""))
    
    exporters:
      # Debug exporter for troubleshooting
      debug:
        verbosity: detailed
        
      # Optional: Export to external systems
      # loki:
      #   endpoint: "http://loki:3100/loki/api/v1/push"
      #   labels:
      #     attributes:
      #       k8s.namespace.name: "namespace"
      #       k8s.event.reason: "reason"
      #       k8s.resource.kind: "kind"
      
      # logging:
      #   loglevel: info
    
    service:
      pipelines:
        # Events pipeline
        logs:
          receivers: [k8s_events]
          processors: [memory_limiter, resource, transform, batch]
          exporters: [debug]
        
        # Optional: Application traces pipeline
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

Apply the collector:

```bash
kubectl apply -f otel-k8seventsreceiver.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 4: Deploy Sample Application to Generate Events

Deploy an application that will generate Kubernetes events:

```yaml
# install-app.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hotrod
  namespace: k8seventsreceiver-demo
  labels:
    app: hotrod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hotrod
  template:
    metadata:
      labels:
        app: hotrod
    spec:
      containers:
      - name: hotrod
        image: jaegertracing/example-hotrod:1.46.0
        args:
        - all
        - --otel-exporter=otlp
        ports:
        - containerPort: 8080
        env:
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: http://k8seventsreceiver-collector:4318
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

---
apiVersion: v1
kind: Service
metadata:
  name: hotrod
  namespace: k8seventsreceiver-demo
spec:
  selector:
    app: hotrod
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: ClusterIP
```

Apply the application:

```bash
kubectl apply -f install-app.yaml

# Wait for the deployment to be ready
kubectl wait --for=condition=available deployment/hotrod --timeout=300s
```

### Step 5: Generate Additional Events

Create some intentional events to verify event collection:

```bash
# Scale deployment to generate scaling events
kubectl scale deployment hotrod --replicas=3

# Wait and scale back down
sleep 10
kubectl scale deployment hotrod --replicas=1

# Create a failing pod to generate error events
kubectl run failing-pod --image=nonexistent:latest --restart=Never || true

# Create and delete a configmap
kubectl create configmap test-config --from-literal=key=value
kubectl delete configmap test-config

# Check current events in the namespace
kubectl get events --sort-by='.lastTimestamp'
```

### Step 6: Verify Event Collection

Check that Kubernetes events are being collected:

```bash
# Check collector logs for Kubernetes events
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=100

# Look for specific event attributes
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "k8s.event"

# Check for event reasons
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -E "(Scheduled|Pulling|Pulled|Created|Started|Killing)"
```

### Step 7: Run Verification Script

Create an automated verification script:

```bash
# Create verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking Kubernetes events receiver functionality..."

# Define the label selector and namespace
LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=${NAMESPACE:-k8seventsreceiver-demo}

# Define the expected Kubernetes event attributes
EXPECTED_ATTRIBUTES=(
  "k8s.event.reason"
  "k8s.event.action"
  "k8s.event.start_time"
  "k8s.event.name"
  "k8s.event.uid"
  "k8s.namespace.name: Str($NAMESPACE)"
  "k8s.event.count"
)

# Get the collector pods
PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "❌ No collector pods found with label $LABEL_SELECTOR in namespace $NAMESPACE"
    exit 1
fi

echo "Found ${#PODS[@]} collector pod(s): ${PODS[*]}"

# Initialize flags to track if attributes are found
declare -A found_flags
for attr in "${EXPECTED_ATTRIBUTES[@]}"; do
    found_flags["$attr"]=false
done

# Check each pod for Kubernetes event data
for POD in "${PODS[@]}"; do
    echo "Checking pod: $POD"
    
    # Get logs from the pod
    LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=200 2>/dev/null || echo "")
    
    if [ -z "$LOGS" ]; then
        echo "⚠️  No logs found in pod $POD"
        continue
    fi
    
    # Search for each expected attribute
    for ATTR in "${EXPECTED_ATTRIBUTES[@]}"; do
        if [ "${found_flags[$ATTR]}" = false ] && echo "$LOGS" | grep -q -- "$ATTR"; then
            echo "✅ \"$ATTR\" found in $POD"
            found_flags["$ATTR"]=true
        fi
    done
done

# Check if all attributes were found
all_found=true
missing_attrs=()

for ATTR in "${EXPECTED_ATTRIBUTES[@]}"; do
    if [ "${found_flags[$ATTR]}" = false ]; then
        echo "❌ \"$ATTR\" not found in any collector pod"
        missing_attrs+=("$ATTR")
        all_found=false
    fi
done

if [ "$all_found" = true ]; then
    echo "🎉 Kubernetes events receiver verification completed successfully!"
    echo "✅ All expected event attributes found"
    echo "✅ Cluster events are being collected as logs"
else
    echo "❌ Kubernetes events receiver verification failed"
    echo "Missing attributes: ${missing_attrs[*]}"
    exit 1
fi
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Namespace Filtering

Collect events from specific namespaces:

```yaml
receivers:
  k8s_events:
    namespaces:
      - production
      - staging
      - monitoring
```

### Event Type Filtering

Filter events using processors:

```yaml
processors:
  filter:
    logs:
      log_record:
        # Only keep Warning events
        - 'attributes["k8s.event.type"] != "Warning"'
        # Filter out noisy events
        - 'attributes["k8s.event.reason"] == "Pulled"'
        - 'attributes["k8s.event.reason"] == "Created"'
```

### Event Enrichment

Add additional context to events:

```yaml
processors:
  transform:
    log_statements:
    - context: log
      statements:
      # Add criticality based on event reason
      - set(attributes["event.criticality"], "high") where attributes["k8s.event.reason"] in ["Failed", "FailedScheduling", "Unhealthy"]
      - set(attributes["event.criticality"], "medium") where attributes["k8s.event.reason"] in ["Warning", "BackOff"]
      - set(attributes["event.criticality"], "low") where attributes["event.criticality"] == nil
      
      # Add cluster region
      - set(attributes["cluster.region"], "us-east-1")
      
      # Extract error information
      - set(attributes["error.message"], body) where attributes["k8s.event.type"] == "Warning"
```

### Multiple Collectors

Deploy separate collectors for different event types:

```yaml
# Events collector for errors only
receivers:
  k8s_events/errors:
    namespaces: ["production"]

processors:
  filter/errors:
    logs:
      log_record:
        - 'attributes["k8s.event.type"] != "Warning"'

service:
  pipelines:
    logs/errors:
      receivers: [k8s_events/errors]
      processors: [filter/errors, batch]
      exporters: [alertmanager]
```

### Event Aggregation

Aggregate similar events:

```yaml
processors:
  groupbyattrs:
    keys:
      - k8s.event.reason
      - k8s.namespace.name
      - k8s.event.involved_object.kind
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector status
kubectl get opentelemetrycollector k8seventsreceiver

# Check RBAC permissions
kubectl auth can-i get events --as=system:serviceaccount:k8seventsreceiver-demo:k8seventsreceiver-sa

# Check service account
kubectl get serviceaccount k8seventsreceiver-sa -o yaml
```

### Common Issues

**Issue: No events being collected**
```bash
# Check RBAC permissions
kubectl describe clusterrolebinding k8seventsreceiver-binding

# Verify events exist in the cluster
kubectl get events -A

# Check collector logs for errors
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i error
```

**Issue: Permission denied errors**
```bash
# Check service account assignment
kubectl get pod -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].spec.serviceAccount}'

# Verify cluster role permissions
kubectl describe clusterrole k8seventsreceiver-role
```

**Issue: Too many events**
```bash
# Add filtering to reduce volume
kubectl patch opentelemetrycollector k8seventsreceiver --type='merge' -p='{"spec":{"config":"processors:\n  filter:\n    logs:\n      log_record:\n        - \"attributes[\\\"k8s.event.type\\\"] != \\\"Warning\\\"\""}}'
```

### Event Analysis

```bash
# Find error events
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "Warning\|Error\|Failed"

# Monitor specific resource types
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "k8s.event.involved_object.kind.*Pod"

# Track deployment events
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "Deployment"
```

## 📊 Event Categories

### Pod Lifecycle Events

Common pod-related events:
- **Scheduled**: Pod assigned to node
- **Pulling**: Pulling container image
- **Pulled**: Container image pulled
- **Created**: Container created
- **Started**: Container started
- **Killing**: Container being terminated

### Deployment Events

Deployment-related events:
- **ScalingReplicaSet**: Replica set scaling
- **SuccessfulCreate**: Pod created successfully
- **SuccessfulDelete**: Pod deleted successfully

### Error Events

Common error events:
- **Failed**: Container failed to start
- **FailedScheduling**: Pod couldn't be scheduled
- **Unhealthy**: Health check failed
- **BackOff**: Restart backoff
- **ImagePullBackOff**: Image pull failed

## 🔐 Security Considerations

1. **RBAC Permissions**: Grant minimal required permissions
2. **Namespace Isolation**: Limit event collection to necessary namespaces
3. **Data Sensitivity**: Events may contain sensitive operational information
4. **Access Control**: Restrict access to event data appropriately

## 📚 Related Patterns

- [k8sclusterreceiver](../k8sclusterreceiver/) - For cluster metrics
- [k8sobjectsreceiver](../k8sobjectsreceiver/) - For custom resource monitoring
- [filelog](../filelog/) - For pod log collection

## 🧹 Cleanup

```bash
# Remove sample application
kubectl delete deployment hotrod
kubectl delete service hotrod

# Remove failing pod (if still exists)
kubectl delete pod failing-pod --ignore-not-found=true

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector k8seventsreceiver

# Remove RBAC configuration
kubectl delete clusterrolebinding k8seventsreceiver-binding
kubectl delete clusterrole k8seventsreceiver-role
kubectl delete serviceaccount k8seventsreceiver-sa

# Remove namespace
kubectl delete namespace k8seventsreceiver-demo
```

## 📖 Additional Resources

- [OpenTelemetry Kubernetes Events Receiver Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/k8seventsreceiver)
- [Kubernetes Events Documentation](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#event-v1-core)
- [Kubernetes RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) 