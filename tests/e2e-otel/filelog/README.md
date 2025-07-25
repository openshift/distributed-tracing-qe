# FileLog Receiver - Kubernetes Pod Log Collection

This blueprint demonstrates how to use the OpenTelemetry FileLog receiver to collect logs from Kubernetes pods using a DaemonSet deployment pattern. This is essential for comprehensive log collection across your cluster.

## 🎯 Use Case

- **Cluster-wide Log Collection**: Collect logs from all pods across the cluster
- **File-based Log Ingestion**: Read logs directly from pod log files
- **Real-time Processing**: Stream logs with minimal latency
- **Flexible Parsing**: Parse various log formats and structures
- **Resource Efficiency**: Daemonset deployment for optimal resource usage

## 📋 What You'll Deploy

- **OpenTelemetry Collector DaemonSet**: Runs on each node to collect logs
- **Security Context Constraints**: OpenShift-specific permissions for file access
- **FileLog Receiver Configuration**: Advanced log collection and parsing
- **Sample Application**: Generates plaintext logs for testing

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Appropriate cluster permissions for DaemonSet deployment

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace filelog-demo

# Set as current namespace
kubectl config set-context --current --namespace=filelog-demo
```

### Step 2: Configure Security Context Constraints (OpenShift)

For OpenShift clusters, create the necessary Security Context Constraints:

```yaml
# security-constraints.yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: otel-filelog-collector-scc
allowPrivilegedContainer: false
requiredDropCapabilities:
- ALL
allowHostDirVolumePlugin: true
volumes:
- configMap
- emptyDir
- hostPath
- projected
- secret
defaultAllowPrivilegeEscalation: false
allowPrivilegeEscalation: false
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
readOnlyRootFilesystem: true
forbiddenSysctls:
- '*'
seccompProfiles:
- runtime/default
users:
- system:serviceaccount:filelog-demo:clusterlogs-collector
```

Apply the SCC:

```bash
oc apply -f security-constraints.yaml
```

### Step 3: Deploy OpenTelemetry Collector with FileLog Receiver

Create the collector configuration:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: clusterlogs
  namespace: filelog-demo
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: daemonset
  
  config:
    receivers:
      filelog:
        include:
          - /var/log/pods/*/*/*.log
        exclude:
          # Exclude OpenTelemetry collector logs to prevent loops
          - /var/log/pods/*/otc-container/*.log
          # Exclude compressed and temporary files
          - "/var/log/pods/*/*/*.gz"
          - "/var/log/pods/*/*/*.log.*"
          - "/var/log/pods/*/*/*.tmp"
          # Exclude system namespaces
          - "/var/log/pods/default_*/*/*.log"
          - "/var/log/pods/kube-*_*/*/*.log"
          - "/var/log/pods/kube_*/*/*.log"
          - "/var/log/pods/openshift-*_*/*/*.log"
        
        # Operators for log parsing and enrichment
        operators:
        # Parse container log format (timestamp + stream + log)
        - type: regex_parser
          id: container_parser
          regex: '^(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z) (?P<stream>stdout|stderr) (?P<logtag>F|P) (?P<log>.*)$'
          parse_from: body
          
        # Parse timestamp
        - type: time_parser
          id: time_parser
          parse_from: attributes.timestamp
          layout: '%Y-%m-%dT%H:%M:%S.%fZ'
          
        # Extract Kubernetes metadata from file path
        - type: regex_parser
          id: k8s_metadata
          regex: '^\/var\/log\/pods\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<pod_uid>[^\/]+)\/(?P<container_name>[^\/]+)\/(?P<restart_count>\d+)\.log$'
          parse_from: attributes.log.file.path
          
        # Move parsed log content to body
        - type: move
          from: attributes.log
          to: body
        
        # Add additional metadata
        - type: add
          field: attributes.source
          value: "kubernetes-filelog"
          
        # Add log level detection for common patterns
        - type: regex_parser
          id: log_level_parser
          regex: '(?i)(?P<level>(error|warn|warning|info|debug|trace|fatal|panic))'
          parse_from: body
          parse_to: attributes
    
    processors:
      batch:
        timeout: 5s
        send_batch_size: 1024
      
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 15
      
      # Add resource attributes
      resource:
        attributes:
        - key: cluster.name
          value: "filelog-demo-cluster"
          action: upsert
        - key: log.source
          value: "kubernetes-filelog"
          action: upsert
      
      # Transform and enrich logs
      transform:
        log_statements:
        - context: log
          statements:
          # Add kubernetes labels as attributes
          - set(attributes["k8s.namespace.name"], attributes["namespace"])
          - set(attributes["k8s.pod.name"], attributes["pod_name"])
          - set(attributes["k8s.container.name"], attributes["container_name"])
          - set(attributes["k8s.pod.uid"], attributes["pod_uid"])
          
          # Normalize log level
          - set(attributes["severity_text"], attributes["level"]) where attributes["level"] != nil
          
          # Add stream information
          - set(attributes["iostream"], attributes["stream"]) where attributes["stream"] != nil
    
    exporters:
      debug:
        verbosity: detailed
      
      # Example: Export to external log system
      # loki:
      #   endpoint: "http://loki:3100/loki/api/v1/push"
      #   labels:
      #     resource:
      #       cluster.name: "cluster"
      #     attributes:
      #       k8s.namespace.name: "namespace"
      #       k8s.pod.name: "pod"
      #       k8s.container.name: "container"
    
    service:
      pipelines:
        logs:
          receivers: [filelog]
          processors: [memory_limiter, resource, transform, batch]
          exporters: [debug]
  
  # Volume mounts for accessing pod logs
  volumeMounts:
  - name: varlogpods
    mountPath: /var/log/pods
    readOnly: true
  - name: varlibdockercontainers
    mountPath: /var/lib/docker/containers
    readOnly: true
  
  volumes:
  - name: varlogpods
    hostPath:
      path: /var/log/pods
  - name: varlibdockercontainers
    hostPath:
      path: /var/lib/docker/containers
  
  # Node selector and tolerations for comprehensive coverage
  nodeSelector:
    kubernetes.io/os: linux
  
  tolerations:
  - operator: Exists
    effect: NoSchedule
  - operator: Exists
    effect: NoExecute
```

Apply the collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for DaemonSet to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 4: Deploy Sample Application

Create an application that generates logs:

```yaml
# app-plaintext-logs.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-plaintext-logs
  namespace: filelog-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-plaintext-logs
  template:
    metadata:
      labels:
        app: app-plaintext-logs
    spec:
      containers:
      - name: log-generator
        image: busybox:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          counter=0
          while true; do
            counter=$((counter + 1))
            
            # Generate different types of logs
            case $((counter % 6)) in
              0)
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO [app-plaintext-logs] Application started successfully"
                ;;
              1)
                echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG [app-plaintext-logs] Processing request #$counter"
                ;;
              2)
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARN [app-plaintext-logs] Memory usage is at 75%"
                ;;
              3)
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR [app-plaintext-logs] Failed to connect to database" >&2
                ;;
              4)
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO [app-plaintext-logs] User login successful: user-$((RANDOM % 1000))"
                ;;
              5)
                echo "$(date '+%Y-%m-%d %H:%M:%S') TRACE [app-plaintext-logs] Function execution completed in $((RANDOM % 100))ms"
                ;;
            esac
            
            # Random delay between 2-8 seconds
            sleep $((2 + RANDOM % 7))
          done
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
```

Apply the application:

```bash
kubectl apply -f app-plaintext-logs.yaml

# Wait for deployment to be ready
kubectl wait --for=condition=available deployment/app-plaintext-logs --timeout=300s
```

### Step 5: Verify Log Collection

Check that logs are being collected:

```bash
# Check collector pods status
kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector

# Check collector logs to see collected data
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector -f --tail=50

# Check application logs to compare
kubectl logs deployment/app-plaintext-logs -f --tail=10
```

### Step 6: Validate Log Processing

Run verification script to ensure logs are properly processed:

```bash
# Create verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking OpenTelemetry FileLog receiver functionality..."

# Get collector pod name
COLLECTOR_POD=$(kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}')

if [ -z "$COLLECTOR_POD" ]; then
    echo "ERROR: No collector pod found"
    exit 1
fi

echo "Using collector pod: $COLLECTOR_POD"

# Check for specific log patterns in collector output
echo "Checking for processed logs..."

# Wait for logs to be processed
sleep 30

# Check for application logs in collector output
kubectl logs $COLLECTOR_POD --tail=100 | grep -q "app-plaintext-logs"
if [ $? -eq 0 ]; then
    echo "✓ Application logs detected in collector output"
else
    echo "✗ Application logs not found in collector output"
    exit 1
fi

# Check for different log levels
for level in INFO ERROR WARN DEBUG; do
    kubectl logs $COLLECTOR_POD --tail=200 | grep -q "$level"
    if [ $? -eq 0 ]; then
        echo "✓ $level level logs detected"
    else
        echo "✗ $level level logs not found"
    fi
done

# Check for Kubernetes metadata
kubectl logs $COLLECTOR_POD --tail=100 | grep -q "k8s.namespace.name"
if [ $? -eq 0 ]; then
    echo "✓ Kubernetes metadata detected"
else
    echo "✗ Kubernetes metadata not found"
fi

echo "Log collection verification completed successfully!"
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Multi-line Log Support

For applications that generate multi-line logs:

```yaml
operators:
- type: multiline_log_parser
  id: multiline_parser
  regex: '^(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})'
  
- type: recombine
  id: multiline_recombine
  combine_field: body
  is_first_entry: body matches "^\\d{4}-\\d{2}-\\d{2}"
  output_field: body
```

### JSON Log Parsing

For applications that log in JSON format:

```yaml
operators:
- type: json_parser
  id: json_parser
  parse_from: attributes.log
  
- type: move
  from: attributes.log.level
  to: attributes.level
  
- type: move
  from: attributes.log.message
  to: body
```

### Performance Optimization

For high-volume log collection:

```yaml
receivers:
  filelog:
    max_concurrent_files: 1024
    max_log_size: 1MiB
    fingerprint_size: 1kb
    
processors:
  batch:
    timeout: 1s
    send_batch_size: 2048
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check DaemonSet status
kubectl get daemonset -l app.kubernetes.io/component=opentelemetry-collector

# Check pod distribution across nodes
kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o wide

# Check resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector
```

### Common Issues

**Issue: Logs not being collected**
```bash
# Check file permissions
kubectl exec -it $COLLECTOR_POD -- ls -la /var/log/pods/

# Check if files are being watched
kubectl logs $COLLECTOR_POD | grep "Started watching file"
```

**Issue: High memory usage**
```bash
# Check memory limits
kubectl describe pod $COLLECTOR_POD | grep -A 5 Limits

# Adjust batch processor settings
kubectl patch opentelemetrycollector clusterlogs --type='merge' -p='{"spec":{"config":"processors:\n  batch:\n    timeout: 2s\n    send_batch_size: 512"}}'
```

## 🔐 Security Considerations

1. **File Access Permissions**: Ensure minimal required permissions
2. **Log Sanitization**: Remove sensitive data before processing
3. **Resource Limits**: Set appropriate CPU and memory limits
4. **Network Policies**: Restrict unnecessary network access

## 📊 Log Analysis Examples

Once logs are collected, you can analyze patterns:

```bash
# Count logs by level
kubectl logs $COLLECTOR_POD --tail=1000 | grep -o '"level":"[^"]*"' | sort | uniq -c

# Find error logs
kubectl logs $COLLECTOR_POD --tail=1000 | grep -i error

# Monitor log volume by namespace
kubectl logs $COLLECTOR_POD --tail=1000 | grep -o '"k8s.namespace.name":"[^"]*"' | sort | uniq -c
```

## 📚 Related Patterns

- [journaldreceiver](../journaldreceiver/) - For system-level log collection
- [k8seventsreceiver](../k8seventsreceiver/) - For Kubernetes event collection
- [transformprocessor](../transformprocessor/) - For advanced log transformation

## 🧹 Cleanup

```bash
# Remove sample application
kubectl delete deployment app-plaintext-logs

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector clusterlogs

# Remove security context constraints (OpenShift)
oc delete securitycontextconstraints otel-filelog-collector-scc

# Remove namespace
kubectl delete namespace filelog-demo
``` 