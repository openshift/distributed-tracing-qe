# OTLP JSON File Receiver - File-Based Telemetry Processing

This blueprint demonstrates how to use the OpenTelemetry OTLP JSON File Receiver to process telemetry data from JSON files. This is essential for batch processing, data archival, offline analysis, and scenarios where telemetry data needs to be stored and processed asynchronously.

## 🎯 Use Case

- **Batch Processing**: Process telemetry data in batches from stored files
- **Data Archival**: Store telemetry data as files for long-term retention
- **Offline Analysis**: Process telemetry data without real-time network connectivity
- **Data Migration**: Transfer telemetry data between systems using file-based transport
- **Disaster Recovery**: Replay telemetry data from backup files

## 📋 What You'll Deploy

- **File Exporter Collector**: Receives live telemetry and exports to JSON files
- **OTLP JSON File Receiver Collector**: Reads JSON files and processes telemetry data
- **Persistent Volume**: Shared storage for JSON telemetry files
- **Tempo Backend**: Final destination for processed traces with Jaeger UI
- **Trace Generator**: Sample application to create test telemetry data

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- Tempo Operator installed (for Tempo backend)
- `kubectl` or `oc` CLI tool configured
- Persistent volume support in the cluster

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace otlpjsonfilereceiver-demo

# Set as current namespace
kubectl config set-context --current --namespace=otlpjsonfilereceiver-demo
```

### Step 2: Create Persistent Volume Claim

Create shared storage for telemetry JSON files:

```yaml
# create-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: otlp-data
  namespace: otlpjsonfilereceiver-demo
  labels:
    app.kubernetes.io/name: otel-jsonfile
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  # Optional: Specify storage class for performance
  # storageClassName: fast-ssd
```

Apply the PVC:

```bash
kubectl apply -f create-pvc.yaml

# Wait for PVC to be bound
kubectl wait --for=condition=Bound pvc/otlp-data --timeout=300s
```

### Step 3: Deploy Tempo Backend

Install Tempo as the final destination for traces:

```yaml
# install-tempo.yaml
apiVersion: tempo.grafana.com/v1alpha1
kind: TempoMonolithic
metadata:
  name: jsonrecv
  namespace: otlpjsonfilereceiver-demo
spec:
  jaegerui:
    enabled: true
    route:
      enabled: true
  
  # Storage configuration
  storage:
    secret:
      name: tempo-storage
      type: s3
  
  # Optional: Resource limits
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "200m"
```

Apply Tempo installation:

```bash
kubectl apply -f install-tempo.yaml

# Wait for Tempo to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tempo --timeout=600s
```

### Step 4: Deploy File Exporter Collector

Create the collector that writes telemetry to JSON files:

```yaml
# fileexporter-otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: fileexporter
  namespace: otlpjsonfilereceiver-demo
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  
  config:
    receivers:
      # OTLP receiver for incoming telemetry
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      # Batch processor for efficiency
      batch:
        timeout: 10s
        send_batch_size: 1024
        send_batch_max_size: 2048
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
      
      # Add file export metadata
      attributes:
        actions:
        - key: export.method
          value: "file"
          action: insert
        - key: export.format
          value: "otlp-json"
          action: insert
        - key: processing.stage
          value: "file-export"
          action: insert
    
    exporters:
      # Debug exporter for monitoring
      debug:
        verbosity: basic
      
      # File exporter for JSON output
      file:
        path: /telemetry-data/telemetrygen-traces.json
        format: json
        
        # Optional: File rotation settings
        # rotation:
        #   max_megabytes: 100
        #   max_days: 7
        #   max_backups: 3
        
        # Optional: Compression
        # compression: gzip
    
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, attributes, batch]
          exporters: [debug, file]
        
        # Optional: Support for metrics and logs
        # metrics:
        #   receivers: [otlp]
        #   processors: [memory_limiter, batch]
        #   exporters: [file/metrics]
        # 
        # logs:
        #   receivers: [otlp]
        #   processors: [memory_limiter, batch]
        #   exporters: [file/logs]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
  
  # Mount persistent volume for file storage
  volumes:
  - name: file
    persistentVolumeClaim:
      claimName: otlp-data
  
  volumeMounts: 
  - name: file
    mountPath: /telemetry-data
```

Apply the file exporter collector:

```bash
kubectl apply -f fileexporter-otel-collector.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=fileexporter --timeout=300s
```

### Step 5: Deploy OTLP JSON File Receiver Collector

Create the collector that reads JSON files and processes telemetry:

```yaml
# otlpjsonfilereceiver-otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otlpjsonfile
  namespace: otlpjsonfilereceiver-demo
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  
  config:
    receivers:
      # OTLP JSON file receiver
      otlpjsonfile:
        # File patterns to monitor
        include:
        - "/telemetry-data/*.json"
        
        # Optional: Exclude patterns
        # exclude:
        # - "/telemetry-data/processed/*.json"
        
        # Optional: Polling interval
        # poll_interval: 1s
        
        # Optional: Start position
        # start_at: beginning  # or 'end'
        
        # Optional: Include file metadata
        # include_file_name: true
        # include_file_path: true
    
    processors:
      # Batch processor for efficiency
      batch:
        timeout: 5s
        send_batch_size: 1024
        send_batch_max_size: 2048
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
      
      # Add file processing metadata
      attributes:
        actions:
        - key: processing.method
          value: "file-receiver"
          action: insert
        - key: processing.format
          value: "otlp-json"
          action: insert
        - key: processing.stage
          value: "file-ingestion"
          action: insert
      
      # Resource processor for additional metadata
      resource:
        attributes:
        - key: service.instance.id
          value: "otlpjsonfile-receiver"
          action: upsert
        - key: deployment.environment
          value: "file-processing"
          action: upsert
    
    exporters:
      # Debug exporter for monitoring
      debug:
        verbosity: basic
      
      # OTLP exporter to Tempo
      otlp:
        endpoint: tempo-jsonrecv:4317
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
        
        # Optional: Compression
        # compression: gzip
    
    service:
      pipelines:
        traces:
          receivers: [otlpjsonfile]
          processors: [memory_limiter, resource, attributes, batch]
          exporters: [debug, otlp]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8889
  
  # Mount persistent volume for file access (read-only)
  volumes:
  - name: file
    persistentVolumeClaim:
      claimName: otlp-data
  
  volumeMounts: 
  - name: file
    mountPath: /telemetry-data
    readOnly: true
  
  # Pod affinity to share storage with file exporter
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/component: opentelemetry-collector
            app.kubernetes.io/managed-by: opentelemetry-operator
            app.kubernetes.io/name: fileexporter-collector
        topologyKey: "kubernetes.io/hostname"
```

Apply the OTLP JSON file receiver collector:

```bash
kubectl apply -f otlpjsonfilereceiver-otel-collector.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=otlpjsonfile --timeout=300s
```

### Step 6: Generate Test Traces

Create traces to test the file-based pipeline:

```yaml
# generate-traces.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces
  namespace: otlpjsonfilereceiver-demo
spec:
  completions: 1
  parallelism: 1
  template:
    spec:
      containers:
      - name: telemetrygen
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - traces
        - --otlp-endpoint=fileexporter-collector:4317
        - --otlp-insecure=true
        - --traces=10
        - --duration=30s
        - --rate=2
        - --service=from-otlp-jsonfile
        - --span-name=file-based-processing
        - --otlp-attributes=processing.type="file-based"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never
  backoffLimit: 4
```

Apply the trace generator:

```bash
kubectl apply -f generate-traces.yaml

# Monitor the job
kubectl logs job/generate-traces -f
```

### Step 7: Verify File-Based Processing

Check that the file-based telemetry pipeline is working:

```bash
# Check file exporter logs
kubectl logs -l app.kubernetes.io/name=fileexporter --tail=50

# Check OTLP JSON file receiver logs
kubectl logs -l app.kubernetes.io/name=otlpjsonfile --tail=50

# Check files are created
kubectl exec deployment/fileexporter -- ls -la /telemetry-data/

# Check file contents
kubectl exec deployment/fileexporter -- head -n 5 /telemetry-data/telemetrygen-traces.json
```

### Step 8: Verify Traces in Tempo

Create verification job to check traces reached Tempo:

```yaml
# verify-traces.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: verify-traces
  namespace: otlpjsonfilereceiver-demo
spec:
  template:
    spec:
      containers:
      - name: verify-traces
        image: curlimages/curl:latest
        command:
        - /bin/sh
        - -c
        args:
        - |
          echo "Verifying traces in Tempo via Jaeger API..."
          
          # Wait for Tempo to be ready
          until curl -s http://tempo-jsonrecv-jaegerui:16686/api/services; do
            echo "Waiting for Jaeger UI to be ready..."
            sleep 5
          done
          
          # Query for traces
          echo "Querying for traces with service 'from-otlp-jsonfile'..."
          curl -v -G http://tempo-jsonrecv-jaegerui:16686/api/traces \
            --data-urlencode "service=from-otlp-jsonfile" \
            --data-urlencode "limit=20" | tee /tmp/jaeger.out
          
          # Check if we have traces
          if command -v jq >/dev/null 2>&1; then
            num_traces=$(jq ".data | length" /tmp/jaeger.out)
            echo "Found $num_traces traces"
            
            if [[ "$num_traces" -gt 0 ]]; then
              echo "✅ File-based telemetry processing successful!"
              echo "✅ Traces found in Tempo backend"
            else
              echo "❌ No traces found in Tempo"
              exit 1
            fi
          else
            echo "jq not available, checking for trace data manually..."
            if grep -q "from-otlp-jsonfile" /tmp/jaeger.out; then
              echo "✅ Traces found in Tempo backend"
            else
              echo "❌ No traces found in Tempo"
              exit 1
            fi
          fi
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never
  backoffLimit: 3
```

Apply and run verification:

```bash
kubectl apply -f verify-traces.yaml

# Wait for verification to complete
kubectl wait --for=condition=complete job/verify-traces --timeout=300s

# Check verification results
kubectl logs job/verify-traces
```

### Step 9: Access Jaeger UI (Optional)

Access the Jaeger UI to visualize traces:

```bash
# Port forward to Jaeger UI
kubectl port-forward svc/tempo-jsonrecv-jaegerui 16686:16686 &

# Open browser to http://localhost:16686
# Search for service: from-otlp-jsonfile
```

## 🔧 Advanced Configuration

### Multiple File Patterns

Monitor different file types:

```yaml
receivers:
  otlpjsonfile/traces:
    include:
    - "/telemetry-data/traces/*.json"
    
  otlpjsonfile/metrics:
    include:
    - "/telemetry-data/metrics/*.json"
    
  otlpjsonfile/logs:
    include:
    - "/telemetry-data/logs/*.json"
```

### File Processing with Operators

Add file metadata and processing:

```yaml
processors:
  transform:
    trace_statements:
    - context: resource
      statements:
      - set(attributes["file.source"], attributes["file.path"])
      - set(attributes["processing.timestamp"], Now())
      
  attributes:
    actions:
    - key: file.processor
      value: "otlpjsonfile"
      action: insert
```

### Batch File Processing

Configure for high-throughput batch processing:

```yaml
receivers:
  otlpjsonfile:
    include:
    - "/telemetry-data/batch/*.json"
    poll_interval: 10s
    start_at: beginning

processors:
  batch:
    timeout: 30s
    send_batch_size: 10000
    send_batch_max_size: 20000
```

### Archive and Cleanup

Process files and move to archive:

```yaml
# Use an init container or sidecar to manage file lifecycle
containers:
- name: file-archiver
  image: busybox
  command:
  - /bin/sh
  - -c
  - |
    while true; do
      # Move processed files to archive
      find /telemetry-data -name "*.json" -mmin +10 -exec mv {} /telemetry-data/archive/ \;
      sleep 60
    done
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check PVC status
kubectl get pvc otlp-data

# Check file creation
kubectl exec deployment/fileexporter -- ls -la /telemetry-data/

# Check file processing
kubectl logs -l app.kubernetes.io/name=otlpjsonfile | grep -i "processing\|file"

# Check Tempo connectivity
kubectl logs -l app.kubernetes.io/name=otlpjsonfile | grep -i "otlp\|tempo"
```

### Common Issues

**Issue: Files not being created**
```bash
# Check file exporter configuration
kubectl get opentelemetrycollector fileexporter -o yaml | grep -A 5 file:

# Check volume mounts
kubectl describe pod -l app.kubernetes.io/name=fileexporter | grep -A 5 "Mounts:"

# Check disk space
kubectl exec deployment/fileexporter -- df -h /telemetry-data/
```

**Issue: Files not being processed**
```bash
# Check include patterns
kubectl get opentelemetrycollector otlpjsonfile -o yaml | grep -A 5 include:

# Check file permissions
kubectl exec deployment/otlpjsonfile -- ls -la /telemetry-data/

# Check polling interval
kubectl logs -l app.kubernetes.io/name=otlpjsonfile | grep -i "polling\|scan"
```

**Issue: Pod affinity problems**
```bash
# Check pod placement
kubectl get pods -o wide

# Check affinity rules
kubectl describe pod -l app.kubernetes.io/name=otlpjsonfile | grep -A 10 "Affinity:"
```

### Performance Monitoring

```bash
# Monitor file processing rate
kubectl logs -l app.kubernetes.io/name=otlpjsonfile | grep -c "ResourceSpans"

# Check batch processing efficiency
kubectl logs -l app.kubernetes.io/name=otlpjsonfile | grep -i "batch.*sent"

# Monitor storage usage
kubectl exec deployment/fileexporter -- du -sh /telemetry-data/
```

## 📊 File-Based Processing Patterns

### Data Lake Integration

Export to data lake formats:

```yaml
exporters:
  file/parquet:
    path: /telemetry-data/parquet/traces.parquet
    format: parquet
    
  file/avro:
    path: /telemetry-data/avro/traces.avro
    format: avro
```

### Batch ETL Pipeline

Process files in scheduled batches:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: telemetry-batch-processor
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: batch-processor
            image: your-etl-image
            command: ["process-telemetry-files.sh"]
```

### Multi-Region File Sync

Synchronize files across regions:

```yaml
containers:
- name: file-sync
  image: rclone/rclone
  command:
  - rclone
  - sync
  - /telemetry-data/
  - s3:backup-bucket/telemetry/
```

## 🔐 Security Considerations

1. **File Permissions**: Ensure proper file and directory permissions
2. **Data Encryption**: Encrypt sensitive telemetry data at rest
3. **Access Control**: Restrict access to telemetry files
4. **Audit Trail**: Log file access and processing activities

## 📚 Related Patterns

- [filelog](../filelog/) - For log file collection
- [filestorageext](../filestorageext/) - For persistent state storage
- [transformprocessor](../transformprocessor/) - For data transformation

## 🧹 Cleanup

```bash
# Remove verification job
kubectl delete job verify-traces

# Remove trace generation job
kubectl delete job generate-traces

# Remove OpenTelemetry collectors
kubectl delete opentelemetrycollector otlpjsonfile fileexporter

# Remove Tempo installation
kubectl delete tempomomolithic jsonrecv

# Remove PVC (this will delete stored data)
kubectl delete pvc otlp-data

# Remove namespace
kubectl delete namespace otlpjsonfilereceiver-demo
```

## 📖 Additional Resources

- [OpenTelemetry OTLP JSON File Receiver Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/otlpjsonfilereceiver)
- [OpenTelemetry File Exporter Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/fileexporter)
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/)
- [Tempo Documentation](https://grafana.com/docs/tempo/) 