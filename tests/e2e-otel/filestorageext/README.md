# File Storage Extension - Persistent State Management

This blueprint demonstrates how to use the OpenTelemetry File Storage Extension to provide persistent storage for collector components that need to maintain state across restarts. This is essential for reliable log processing, checkpoint management, and ensuring data consistency.

## 🎯 Use Case

- **State Persistence**: Maintain receiver state across collector restarts
- **Data Reliability**: Prevent data loss during collector downtime
- **Checkpoint Management**: Track processing positions in log files
- **Recovery Capability**: Resume processing from last known position
- **Data Consistency**: Ensure exactly-once or at-least-once delivery semantics

## 📋 What You'll Deploy

- **Primary OpenTelemetry Collector**: Receives and processes logs via OTLP
- **Sidecar Collector**: File log collection with persistent state management
- **File Storage Extension**: Provides persistent storage for receiver state
- **Log Generator Application**: Creates continuous log streams for testing
- **Shared Volume**: Persistent storage for state files

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- Understanding of persistent volumes (optional but recommended)

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace filestorageext-demo

# Set as current namespace
kubectl config set-context --current --namespace=filestorageext-demo
```

### Step 2: Deploy Primary OpenTelemetry Collector

Create the main collector that will receive logs from the sidecar:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: filestorageext
  namespace: filestorageext-demo
spec:
  mode: deployment
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  
  config:
    receivers:
      # OTLP receiver for logs from sidecar
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      # Batch processor for efficiency
      batch:
        timeout: 5s
        send_batch_size: 1024
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
      
      # Resource processor for metadata
      resource:
        attributes:
        - key: service.name
          value: "filestorageext-demo"
          action: upsert
        - key: collector.type
          value: "primary"
          action: upsert
    
    exporters:
      # Debug exporter to see processed logs
      debug:
        verbosity: detailed
      
      # Optional: Add other exporters as needed
      # logging:
      #   loglevel: info
    
    service:
      pipelines:
        logs:
          receivers: [otlp]
          processors: [memory_limiter, resource, batch]
          exporters: [debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

Apply the primary collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 3: Deploy Sidecar Collector with File Storage Extension

Create the sidecar collector with file storage extension:

```yaml
# otel-filestorageext-sidecar.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: filestorageext-sidecar
  namespace: filestorageext-demo
spec:
  mode: sidecar
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  
  config:
    receivers:
      # File log receiver with persistent storage
      filelog:
        # Reference to file storage extension
        storage: file_storage
        
        # Log files to monitor
        include: [/log-data/*.log]
        
        # Log parsing configuration
        operators:
        # Parse application log format
        - type: regex_parser
          id: app_log_parser
          regex: '^(?P<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}) - (?P<logger>\S+) - (?P<sev>\S+) - (?P<message>.*)$'
          timestamp:
            parse_from: attributes.time
            layout: '%Y-%m-%d %H:%M:%S'
          severity:
            parse_from: attributes.sev
            
        # Add metadata
        - type: add
          field: attributes.source
          value: "file-storage-demo"
          
        - type: add
          field: attributes.storage.type
          value: "persistent"
    
    processors:
      # Batch processing for efficiency
      batch:
        timeout: 2s
        send_batch_size: 512
        send_batch_max_size: 1024
      
      # Resource attributes
      resource:
        attributes:
        - key: collector.type
          value: "sidecar"
          action: upsert
        - key: storage.backend
          value: "file_storage"
          action: upsert
    
    exporters:
      # Forward to primary collector
      otlp:
        endpoint: filestorageext-collector:4317
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
          max_elapsed_time: 300s
    
    extensions:
      # File storage extension configuration
      file_storage:
        # Directory for persistent state files
        directory: /filestorageext/data
        
        # Timeout for storage operations
        timeout: 1s
        
        # Compaction settings for storage optimization
        compaction:
          on_start: true
          directory: /filestorageext/compaction
          max_transaction_size: 65536
          
        # Force sync to disk for durability
        fsync: true
    
    service:
      # Enable the file storage extension
      extensions: [file_storage]
      
      pipelines:
        logs:
          receivers: [filelog]
          processors: [resource, batch]
          exporters: [otlp]
  
  # Volume mounts for log files and persistent storage
  volumeMounts:
  - name: log-data
    mountPath: /log-data
  - name: filestorageext
    mountPath: /filestorageext/data
  - name: filestorageext-compaction
    mountPath: /filestorageext/compaction
```

Apply the sidecar collector:

```bash
kubectl apply -f otel-filestorageext-sidecar.yaml
```

### Step 4: Deploy Log Generator Application

Create an application that generates continuous logs:

```yaml
# app-plaintext-logs.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-log-plaintext-config
  namespace: filestorageext-demo
data:
  ocp_logtest.cfg: --rate 10.0 -o /log-data/app-log-plaintext.log

---
apiVersion: v1
kind: ReplicationController
metadata:
  labels:
    run: otel-logtest-plaintext
    test: otel-logtest-plaintext
  name: app-log-plaintext-rc
  namespace: filestorageext-demo
spec:
  replicas: 1
  template:
    metadata:
      annotations:
        containerType.logging.openshift.io/app-log-plaintext: app-log-plaintext
        sidecar.opentelemetry.io/inject: "true"
      generateName: otel-logtest-
      labels:
        run: otel-logtest-plaintext
        test: otel-logtest-plaintext
    spec:
      containers:
      - name: app-log-plaintext
        image: quay.io/openshifttest/ocp-logtest@sha256:6e2973d7d454ce412ad90e99ce584bf221866953da42858c4629873e53778606
        imagePullPolicy: IfNotPresent
        env: []
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
          privileged: false
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        terminationMessagePath: /dev/termination-log
        volumeMounts:
        - mountPath: /log-data
          name: log-data
        - mountPath: /var/lib/svt
          name: config
        - mountPath: /filestorageext/data
          name: filestorageext
        - mountPath: /filestorageext/compaction
          name: filestorageext-compaction
      
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      
      volumes:
      - configMap:
          name: app-log-plaintext-config
        name: config
      - name: log-data
        emptyDir: {}
      - name: filestorageext
        emptyDir: {}
      - name: filestorageext-compaction
        emptyDir: {}
```

Apply the log generator:

```bash
kubectl apply -f app-plaintext-logs.yaml

# Wait for the replication controller to be ready
kubectl wait --for=condition=ready pod -l run=otel-logtest-plaintext --timeout=300s
```

### Step 5: Verify Log Processing

Check that logs are being processed through the file storage extension:

```bash
# Check primary collector logs
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=50

# Check sidecar collector logs
kubectl logs -l app.kubernetes.io/name=filestorageext-sidecar --tail=50

# Check log generator application
kubectl logs replicationcontroller/app-log-plaintext-rc --tail=20
```

### Step 6: Verify File Storage Extension

Check that the file storage extension is creating persistent state files:

```bash
# Check for storage files in the data directory
kubectl exec replicationcontroller/app-log-plaintext-rc -- ls -la /filestorageext/data/

# Check for compaction files
kubectl exec replicationcontroller/app-log-plaintext-rc -- ls -la /filestorageext/compaction/

# Look for receiver state files
kubectl exec replicationcontroller/app-log-plaintext-rc -- find /filestorageext -name "*receiver_filelog_*" -type f
```

### Step 7: Test Persistence with Restart

Test that state is preserved across collector restarts:

```bash
# Record current log position
CURRENT_LOGS=$(kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | wc -l)
echo "Current log count: $CURRENT_LOGS"

# Restart the sidecar collector
kubectl patch opentelemetrycollector filestorageext-sidecar -p '{"spec":{"replicas":0}}'
sleep 10
kubectl patch opentelemetrycollector filestorageext-sidecar -p '{"spec":{"replicas":1}}'

# Wait for collector to restart
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=filestorageext-sidecar --timeout=300s

# Check that processing resumes from where it left off
sleep 30
NEW_LOGS=$(kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | wc -l)
echo "New log count: $NEW_LOGS"

if [ $NEW_LOGS -gt $CURRENT_LOGS ]; then
    echo "✅ Log processing resumed after restart"
else
    echo "⚠️  Logs may not be processing after restart"
fi
```

### Step 8: Run Verification Scripts

Create and run verification scripts:

```bash
# Create file storage verification script
cat > check_filestorageext.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking file storage extension functionality..."

# Define the directories to check
directories=("/filestorageext/compaction" "/filestorageext/data")

# Define the file pattern to check for
file_pattern="receiver_filelog_"

# Initialize a variable to keep track of the number of files found
files_found=0
max_attempts=30
attempt=0

echo "Searching for file storage state files..."

# Keep running the loop until all files are found or max attempts reached
while [ "$files_found" -ne "${#directories[@]}" ] && [ $attempt -lt $max_attempts ]; do
    # Reset the counter
    files_found=0
    
    # Loop through the directories
    for dir in "${directories[@]}"; do
        # Check if files exist in the directory
        if kubectl exec replicationcontroller/app-log-plaintext-rc -- ls "$dir" 2>/dev/null | grep -q "$file_pattern"; then
            echo "✅ File storage files found in $dir"
            ((files_found++))
        else
            echo "⚠️  File storage files not found in $dir (attempt $((attempt+1)))"
        fi
    done
    
    if [ "$files_found" -ne "${#directories[@]}" ]; then
        sleep 2
        ((attempt++))
    fi
done

if [ "$files_found" -eq "${#directories[@]}" ]; then
    echo "🎉 File storage extension verification completed successfully!"
    echo "✅ State files found in all expected directories"
else
    echo "❌ File storage extension verification failed"
    echo "❌ State files not found in all directories after $max_attempts attempts"
    exit 1
fi
EOF

chmod +x check_filestorageext.sh
./check_filestorageext.sh

# Create log processing verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking log processing functionality..."

# Define the expected log attributes
EXPECTED_STRINGS=(
    "log.file.name: Str(app-log-plaintext.log)"
    "logger: Str(SVTLogger)"
    "message: Str("
    "time: Str("
    "sev: Str(INFO)"
    "SVTLogger - INFO - app-log-plaintext-"
)

# Get collector pods
PODS=$(kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[*].metadata.name}')

if [ -z "$PODS" ]; then
    echo "❌ No collector pods found"
    exit 1
fi

echo "Found collector pods: $PODS"

# Initialize flags for each search string
declare -A found_flags
for string in "${EXPECTED_STRINGS[@]}"; do
    found_flags["$string"]=false
done

# Search through pod logs
for POD in $PODS; do
    echo "Checking pod: $POD"
    
    LOGS=$(kubectl logs $POD --tail=100 2>/dev/null || echo "")
    
    if [ -z "$LOGS" ]; then
        echo "⚠️  No logs found in pod $POD"
        continue
    fi
    
    # Check for each expected string
    for STRING in "${EXPECTED_STRINGS[@]}"; do
        if [ "${found_flags[$STRING]}" = false ] && echo "$LOGS" | grep -q -- "$STRING"; then
            echo "✅ \"$STRING\" found in $POD"
            found_flags["$STRING"]=true
        fi
    done
done

# Check if all strings were found
all_found=true
for STRING in "${EXPECTED_STRINGS[@]}"; do
    if [ "${found_flags[$STRING]}" = false ]; then
        echo "❌ \"$STRING\" not found in any collector pod"
        all_found=false
    fi
done

if [ "$all_found" = true ]; then
    echo "🎉 Log processing verification completed successfully!"
    echo "✅ All expected log attributes found"
else
    echo "❌ Log processing verification failed"
    exit 1
fi
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Persistent Volume Configuration

For persistent storage, use persistent volumes:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: filestorageext-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: fast-ssd

---
# Update collector to use PVC
volumeMounts:
- name: filestorageext-storage
  mountPath: /filestorageext/data
volumes:
- name: filestorageext-storage
  persistentVolumeClaim:
    claimName: filestorageext-pvc
```

### Advanced Storage Configuration

Configure storage extension for high-throughput scenarios:

```yaml
extensions:
  file_storage:
    directory: /filestorageext/data
    timeout: 5s
    
    # Compaction settings for performance
    compaction:
      on_start: true
      on_rebound: true
      directory: /filestorageext/compaction
      max_transaction_size: 1048576  # 1MB
      rebound_needed_threshold_mib: 100
      rebound_trigger_threshold_mib: 10
      
    # Sync settings for durability vs performance
    fsync: true
    
    # Optional: Set maximum storage size
    # max_storage_size: 1073741824  # 1GB
```

### Multiple Storage Extensions

Use different storage extensions for different receivers:

```yaml
extensions:
  file_storage/logs:
    directory: /storage/logs
    compaction:
      directory: /storage/logs/compaction
      
  file_storage/metrics:
    directory: /storage/metrics
    compaction:
      directory: /storage/metrics/compaction

receivers:
  filelog:
    storage: file_storage/logs
    
  hostmetrics:
    storage: file_storage/metrics
```

### State Migration

Handle storage migration between versions:

```yaml
extensions:
  file_storage:
    directory: /filestorageext/data
    
    # Migration settings
    compaction:
      on_start: true
      cleanup_on_error_count: 3
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check storage extension status
kubectl logs -l app.kubernetes.io/name=filestorageext-sidecar | grep -i "file_storage"

# Check available disk space
kubectl exec replicationcontroller/app-log-plaintext-rc -- df -h /filestorageext/

# Monitor storage file sizes
kubectl exec replicationcontroller/app-log-plaintext-rc -- find /filestorageext -type f -exec ls -lh {} \;
```

### Common Issues

**Issue: Storage files not created**
```bash
# Check directory permissions
kubectl exec replicationcontroller/app-log-plaintext-rc -- ls -la /filestorageext/

# Check extension configuration
kubectl get opentelemetrycollector filestorageext-sidecar -o yaml | grep -A 10 file_storage
```

**Issue: High disk usage**
```bash
# Check compaction settings
kubectl exec replicationcontroller/app-log-plaintext-rc -- ls -la /filestorageext/compaction/

# Manually trigger compaction by restarting collector
kubectl rollout restart deployment filestorageext-sidecar
```

**Issue: State not persisting**
```bash
# Check fsync setting
kubectl get opentelemetrycollector filestorageext-sidecar -o yaml | grep fsync

# Verify volume mounts
kubectl describe pod -l app.kubernetes.io/name=filestorageext-sidecar | grep -A 5 "Mounts:"
```

### Performance Monitoring

```bash
# Monitor storage operation latency
kubectl logs -l app.kubernetes.io/name=filestorageext-sidecar | grep -i "timeout\|latency"

# Check compaction frequency
kubectl logs -l app.kubernetes.io/name=filestorageext-sidecar | grep -i "compaction"
```

## 📊 Storage Patterns

### Checkpoint Management

Track processing positions for reliable delivery:

```yaml
receivers:
  filelog:
    storage: file_storage
    include_file_name: false
    include_file_path: true
    
    # Checkpoint frequency
    start_at: beginning
    fingerprint_size: 1kb
    max_log_size: 1MiB
```

### State Cleanup

Automatic cleanup of old state files:

```yaml
extensions:
  file_storage:
    compaction:
      on_start: true
      cleanup_on_error_count: 5
      max_transaction_size: 65536
```

### Backup and Recovery

Backup storage state for disaster recovery:

```bash
# Create backup of storage state
kubectl exec replicationcontroller/app-log-plaintext-rc -- tar -czf /tmp/storage-backup.tar.gz /filestorageext/data/

# Copy backup to local machine
kubectl cp replicationcontroller/app-log-plaintext-rc:/tmp/storage-backup.tar.gz ./storage-backup.tar.gz
```

## 🔐 Security Considerations

1. **File Permissions**: Ensure proper permissions on storage directories
2. **Data Encryption**: Consider encrypting persistent volumes
3. **Access Control**: Restrict access to storage directories
4. **Backup Security**: Secure backup data appropriately

## 📚 Related Patterns

- [filelog](../filelog/) - For file-based log collection
- [routingconnector](../routingconnector/) - For complex data routing
- [transformprocessor](../transformprocessor/) - For data transformation

## 🧹 Cleanup

```bash
# Remove application and collectors
kubectl delete replicationcontroller app-log-plaintext-rc
kubectl delete configmap app-log-plaintext-config
kubectl delete opentelemetrycollector filestorageext-sidecar filestorageext

# Remove persistent volumes (if used)
kubectl delete pvc filestorageext-pvc

# Remove namespace
kubectl delete namespace filestorageext-demo
```

## 📖 Additional Resources

- [OpenTelemetry File Storage Extension Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/extension/storage/filestorage)
- [OpenTelemetry Storage Interface](https://github.com/open-telemetry/opentelemetry-collector/tree/main/extension/storage)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) 