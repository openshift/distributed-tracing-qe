# Kubernetes Objects Receiver - Custom Resource Monitoring

This blueprint demonstrates how to use the OpenTelemetry Kubernetes Objects Receiver to collect and monitor any Kubernetes resource type as structured logs. This is essential for tracking custom resources, monitoring resource state changes, and maintaining an audit trail of Kubernetes object lifecycle.

## 🎯 Use Case

- **Custom Resource Monitoring**: Track custom Kubernetes resources and CRDs
- **Resource State Tracking**: Monitor state changes across all Kubernetes objects
- **Audit Trail**: Maintain detailed logs of resource creation, updates, and deletion
- **Compliance Monitoring**: Track resource configurations for compliance requirements
- **Operational Insights**: Understand resource relationships and dependencies

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with Kubernetes objects receiver
- **Service Account & RBAC**: Permissions to read specified Kubernetes resources
- **Resource Collection**: Automated collection of pods and events as structured logs
- **Debug Export**: Detailed logging of collected Kubernetes object data

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Cluster admin permissions (for RBAC setup)

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace k8sobjectsreceiver-demo

# Set as current namespace
kubectl config set-context --current --namespace=k8sobjectsreceiver-demo
```

### Step 2: Create Service Account and RBAC

Create permissions to access Kubernetes objects:

```yaml
# rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k8sobjectsreceiver-sa
  namespace: k8sobjectsreceiver-demo

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8sobjectsreceiver-role
rules:
# Core API objects
- apiGroups: [""]
  resources:
  - events
  - pods
  - services
  - configmaps
  - secrets
  - nodes
  - namespaces
  verbs:
  - get
  - list
  - watch

# Events API group
- apiGroups: ["events.k8s.io"]
  resources:
  - events
  verbs:
  - get
  - list
  - watch

# Apps API group
- apiGroups: ["apps"]
  resources:
  - deployments
  - replicasets
  - daemonsets
  - statefulsets
  verbs:
  - get
  - list
  - watch

# Optional: Custom resource definitions
- apiGroups: ["apiextensions.k8s.io"]
  resources:
  - customresourcedefinitions
  verbs:
  - get
  - list
  - watch

# Optional: OpenTelemetry CRDs
- apiGroups: ["opentelemetry.io"]
  resources:
  - opentelemetrycollectors
  - instrumentations
  verbs:
  - get
  - list
  - watch

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: k8sobjectsreceiver-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8sobjectsreceiver-role
subjects:
- kind: ServiceAccount
  name: k8sobjectsreceiver-sa
  namespace: k8sobjectsreceiver-demo
```

Apply the RBAC configuration:

```bash
kubectl apply -f rbac.yaml
```

### Step 3: Deploy OpenTelemetry Collector with K8s Objects Receiver

Create the collector configuration:

```yaml
# otel-k8sobjectsreceiver.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: k8sobjectsreceiver
  namespace: k8sobjectsreceiver-demo
spec:
  mode: deployment
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: k8sobjectsreceiver-sa
  
  config:
    receivers:
      # Kubernetes objects receiver
      k8sobjects:
        # Authentication type
        auth_type: serviceAccount
        
        # Objects to collect
        objects:
        # Collect pods with pull mode (snapshot at intervals)
        - name: pods
          mode: pull
          interval: 30s
          namespaces: [k8sobjectsreceiver-demo, default]
          
        # Collect events with watch mode (real-time)
        - name: events
          mode: watch
          namespaces: [k8sobjectsreceiver-demo, default]
          
        # Collect deployments
        - name: deployments
          mode: pull
          interval: 60s
          group: apps
          version: v1
          
        # Collect services
        - name: services
          mode: pull
          interval: 60s
          
        # Optional: Collect custom resources
        # - name: opentelemetrycollectors
        #   mode: watch
        #   group: opentelemetry.io
        #   version: v1beta1
    
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
          value: "k8sobjects-demo-cluster"
          action: upsert
        - key: log.source
          value: "kubernetes-objects"
          action: upsert
      
      # Transform processor to enrich object data
      transform:
        log_statements:
        - context: log
          statements:
          # Extract object metadata
          - set(attributes["k8s.object.kind"], attributes["k8s.resource.name"]) where attributes["k8s.resource.name"] != nil
          - set(attributes["k8s.object.namespace"], attributes["k8s.namespace.name"]) where attributes["k8s.namespace.name"] != nil
          
          # Add object lifecycle information
          - set(attributes["object.lifecycle.phase"], "active") where attributes["k8s.resource.name"] != nil
          
          # Extract creation timestamp if available
          - set(attributes["object.created_at"], attributes["k8s.resource.creation_timestamp"]) where attributes["k8s.resource.creation_timestamp"] != nil
          
          # Add event-specific information
          - set(attributes["event.reason"], attributes["k8s.event.reason"]) where attributes["k8s.event.reason"] != nil
          - set(attributes["event.type"], attributes["k8s.event.type"]) where attributes["k8s.event.type"] != nil
    
    exporters:
      # Debug exporter for detailed logging
      debug:
        verbosity: detailed
        
      # Optional: Export to external systems
      # loki:
      #   endpoint: "http://loki:3100/loki/api/v1/push"
      #   labels:
      #     attributes:
      #       k8s.resource.name: "resource"
      #       k8s.namespace.name: "namespace"
      
      # file:
      #   path: /tmp/k8s-objects.log
      #   rotation:
      #     max_megabytes: 100
      #     max_days: 7
    
    service:
      pipelines:
        logs:
          receivers: [k8sobjects]
          processors: [memory_limiter, resource, transform, batch]
          exporters: [debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

Apply the collector:

```bash
kubectl apply -f otel-k8sobjectsreceiver.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 4: Create Sample Resources

Generate some Kubernetes resources to test the receiver:

```yaml
# sample-resources.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: k8sobjectsreceiver-demo
  labels:
    app: sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: app
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"

---
apiVersion: v1
kind: Service
metadata:
  name: sample-service
  namespace: k8sobjectsreceiver-demo
spec:
  selector:
    app: sample-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: sample-config
  namespace: k8sobjectsreceiver-demo
data:
  config.yaml: |
    app:
      name: sample-app
      version: 1.0.0
      debug: true
```

Apply the sample resources:

```bash
kubectl apply -f sample-resources.yaml

# Wait for deployment to be ready
kubectl wait --for=condition=available deployment/sample-app --timeout=300s
```

### Step 5: Generate Object Changes

Create some object changes to trigger collection:

```bash
# Scale the deployment to generate change events
kubectl scale deployment sample-app --replicas=3

# Update the configmap
kubectl patch configmap sample-config -p '{"data":{"config.yaml":"app:\n  name: sample-app\n  version: 1.1.0\n  debug: false"}}'

# Create and delete a temporary pod
kubectl run temp-pod --image=busybox --restart=Never -- sleep 30
sleep 5
kubectl delete pod temp-pod

# Check current objects in the namespace
kubectl get all,configmaps -n k8sobjectsreceiver-demo
```

### Step 6: Verify Object Collection

Check that Kubernetes objects are being collected:

```bash
# Check collector logs for object data
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=100

# Look for specific object types
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -E "(pods|events|deployments)"

# Check for object metadata
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "k8s.resource.name"
```

### Step 7: Run Verification Script

Create and run verification script:

```bash
# Create verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking Kubernetes objects receiver functionality..."

# Define the label selector and namespace
LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=${NAMESPACE:-k8sobjectsreceiver-demo}

# Define expected patterns for Kubernetes object data
EXPECTED_PATTERNS=(
    'Body: Map({"object":'
    'k8s.resource.name'
    'event.domain'
    'event.name'
    'k8s.namespace.name'
    'k8s.object.kind'
)

# Get collector pods
PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "❌ No collector pods found with label $LABEL_SELECTOR in namespace $NAMESPACE"
    exit 1
fi

echo "Found ${#PODS[@]} collector pod(s): ${PODS[*]}"

# Initialize flags for tracking found patterns
declare -A found_flags
for pattern in "${EXPECTED_PATTERNS[@]}"; do
    found_flags["$pattern"]=false
done

# Check each pod for Kubernetes object data
for POD in "${PODS[@]}"; do
    echo "Checking pod: $POD"
    
    # Get logs from the pod
    LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=500 2>/dev/null || echo "")
    
    if [ -z "$LOGS" ]; then
        echo "⚠️  No logs found in pod $POD"
        continue
    fi
    
    # Search for each expected pattern
    for PATTERN in "${EXPECTED_PATTERNS[@]}"; do
        if [ "${found_flags[$PATTERN]}" = false ] && echo "$LOGS" | grep -q -- "$PATTERN"; then
            echo "✅ \"$PATTERN\" found in $POD"
            found_flags["$PATTERN"]=true
        fi
    done
done

# Check if all patterns were found
all_found=true
missing_patterns=()

for PATTERN in "${EXPECTED_PATTERNS[@]}"; do
    if [ "${found_flags[$PATTERN]}" = false ]; then
        echo "❌ \"$PATTERN\" not found in any collector pod"
        missing_patterns+=("$PATTERN")
        all_found=false
    fi
done

if [ "$all_found" = true ]; then
    echo "🎉 Kubernetes objects receiver verification completed successfully!"
    echo "✅ All expected object data patterns found"
    echo "✅ Kubernetes objects are being collected as structured logs"
else
    echo "❌ Kubernetes objects receiver verification failed"
    echo "Missing patterns: ${missing_patterns[*]}"
    exit 1
fi
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Custom Resource Collection

Monitor custom resources and CRDs:

```yaml
receivers:
  k8sobjects:
    objects:
    # Monitor OpenTelemetry collectors
    - name: opentelemetrycollectors
      mode: watch
      group: opentelemetry.io
      version: v1beta1
      
    # Monitor Prometheus instances
    - name: prometheuses
      mode: pull
      interval: 120s
      group: monitoring.coreos.com
      version: v1
      
    # Monitor custom application CRDs
    - name: applications
      mode: watch
      group: argoproj.io
      version: v1alpha1
```

### Namespace and Label Filtering

Filter objects by namespace and labels:

```yaml
receivers:
  k8sobjects:
    objects:
    - name: pods
      mode: pull
      interval: 30s
      namespaces: [production, staging]
      label_selector: "app=critical,tier=frontend"
      field_selector: "status.phase=Running"
```

### Multiple Collection Modes

Use different modes for different object types:

```yaml
receivers:
  k8sobjects:
    objects:
    # Real-time monitoring for critical events
    - name: events
      mode: watch
      namespaces: [production]
      
    # Periodic snapshots for configuration drift
    - name: configmaps
      mode: pull
      interval: 300s  # 5 minutes
      
    # Frequent monitoring for deployments
    - name: deployments
      mode: pull
      interval: 60s
      group: apps
      version: v1
```

### Object Data Transformation

Transform object data for specific use cases:

```yaml
processors:
  transform:
    log_statements:
    - context: log
      statements:
      # Extract pod status information
      - set(attributes["pod.status"], body["object"]["status"]["phase"]) where body["object"]["kind"] == "Pod"
      
      # Extract deployment replica information
      - set(attributes["deployment.replicas.desired"], body["object"]["spec"]["replicas"]) where body["object"]["kind"] == "Deployment"
      - set(attributes["deployment.replicas.ready"], body["object"]["status"]["readyReplicas"]) where body["object"]["kind"] == "Deployment"
      
      # Extract service type
      - set(attributes["service.type"], body["object"]["spec"]["type"]) where body["object"]["kind"] == "Service"
      
      # Add compliance tags
      - set(attributes["compliance.required"], "true") where body["object"]["metadata"]["labels"]["compliance"] == "required"
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector status
kubectl get opentelemetrycollector k8sobjectsreceiver

# Check RBAC permissions
kubectl auth can-i get pods --as=system:serviceaccount:k8sobjectsreceiver-demo:k8sobjectsreceiver-sa
kubectl auth can-i watch events --as=system:serviceaccount:k8sobjectsreceiver-demo:k8sobjectsreceiver-sa

# Check available objects in cluster
kubectl api-resources
```

### Common Issues

**Issue: Objects not being collected**
```bash
# Check RBAC permissions for specific resources
kubectl describe clusterrole k8sobjectsreceiver-role

# Verify objects exist in specified namespaces
kubectl get pods,events -n k8sobjectsreceiver-demo

# Check collector logs for errors
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i error
```

**Issue: Permission denied errors**
```bash
# Check service account assignment
kubectl get pod -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].spec.serviceAccount}'

# Verify cluster role binding
kubectl describe clusterrolebinding k8sobjectsreceiver-binding
```

**Issue: High volume of data**
```bash
# Add namespace filtering
kubectl patch opentelemetrycollector k8sobjectsreceiver --type='merge' -p='{"spec":{"config":"receivers:\n  k8sobjects:\n    objects:\n    - name: pods\n      namespaces: [\"k8sobjectsreceiver-demo\"]"}}'

# Increase collection intervals
kubectl patch opentelemetrycollector k8sobjectsreceiver --type='merge' -p='{"spec":{"config":"receivers:\n  k8sobjects:\n    objects:\n    - name: pods\n      interval: 300s"}}'
```

### Performance Optimization

```bash
# Monitor collector resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Check collection intervals and adjust based on needs
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "k8sobjects.*collected"
```

## 📊 Object Collection Strategies

### Configuration Monitoring

Track configuration changes:

```yaml
objects:
- name: configmaps
  mode: watch
- name: secrets
  mode: watch
- name: customresourcedefinitions
  mode: pull
  interval: 3600s
```

### Application Lifecycle Monitoring

Monitor application deployments:

```yaml
objects:
- name: deployments
  mode: pull
  interval: 60s
  group: apps
  version: v1
- name: replicasets
  mode: pull
  interval: 120s
  group: apps
  version: v1
- name: pods
  mode: pull
  interval: 30s
```

### Security and Compliance Monitoring

Monitor security-related objects:

```yaml
objects:
- name: networkpolicies
  mode: watch
  group: networking.k8s.io
  version: v1
- name: podsecuritypolicies
  mode: watch
  group: policy
  version: v1beta1
- name: rolebindings
  mode: watch
  group: rbac.authorization.k8s.io
  version: v1
```

### Infrastructure Monitoring

Monitor cluster infrastructure:

```yaml
objects:
- name: nodes
  mode: pull
  interval: 300s
- name: persistentvolumes
  mode: pull
  interval: 600s
- name: storageclasses
  mode: pull
  interval: 3600s
  group: storage.k8s.io
  version: v1
```

## 🔐 Security Considerations

1. **RBAC Permissions**: Grant only necessary permissions for required resources
2. **Sensitive Data**: Be cautious when collecting secrets or other sensitive objects
3. **Namespace Isolation**: Use namespace filtering to limit scope
4. **Data Retention**: Implement appropriate data retention policies

## 📚 Related Patterns

- [k8seventsreceiver](../k8seventsreceiver/) - For Kubernetes event collection
- [k8sclusterreceiver](../k8sclusterreceiver/) - For cluster metrics
- [transformprocessor](../transformprocessor/) - For object data transformation

## 🧹 Cleanup

```bash
# Remove sample resources
kubectl delete deployment sample-app
kubectl delete service sample-service
kubectl delete configmap sample-config

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector k8sobjectsreceiver

# Remove RBAC configuration
kubectl delete clusterrolebinding k8sobjectsreceiver-binding
kubectl delete clusterrole k8sobjectsreceiver-role
kubectl delete serviceaccount k8sobjectsreceiver-sa

# Remove namespace
kubectl delete namespace k8sobjectsreceiver-demo
```

## 📖 Additional Resources

- [OpenTelemetry Kubernetes Objects Receiver Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/k8sobjectsreceiver)
- [Kubernetes API Reference](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/)
- [Custom Resource Definitions](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) 