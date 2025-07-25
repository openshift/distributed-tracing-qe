# OpenTelemetry File Storage Extension Test

This test demonstrates the OpenTelemetry File Storage Extension configuration for persistent state management in telemetry pipelines.

## 🎯 What This Test Does

The test validates that the File Storage Extension can:
- Provide persistent storage for the filelog receiver to track file read positions
- Store state information across collector restarts
- Use compaction for storage optimization
- Handle file synchronization (fsync) for data durability
- Process application logs from files using a sidecar pattern

## 📋 Test Resources

### 1. Namespace RBAC and Security Configuration
The test configures OpenShift-specific security settings:
```bash
# Role binding for pod view access
kubectl create rolebinding default-view-$NAMESPACE --role=pod-view --serviceaccount=$NAMESPACE:ta

# Security context constraints
kubectl annotate namespace ${NAMESPACE} openshift.io/sa.scc.uid-range=1000/1000 --overwrite
kubectl annotate namespace ${NAMESPACE} openshift.io/sa.scc.supplemental-groups=3000/1000 --overwrite
```

### 2. Main Collector (Debug Output)
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: filestorageext
spec:
  mode: deployment
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
          http:
    processors:
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        logs:
          receivers: [otlp]
          processors: []
          exporters: [debug]
```

### 3. Sidecar Collector with File Storage Extension
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: filestorageext-sidecar
spec:
  mode: sidecar
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  config: |
    receivers:
      filelog:
        storage: file_storage
        include: [ /log-data/*.log ]
        operators:
          - type: regex_parser
            regex: '^(?P<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}) - (?P<logger>\S+) - (?P<sev>\S+) - (?P<message>.*)$'
            timestamp:
              parse_from: attributes.time
              layout: '%Y-%m-%d %H:%M:%S'
            severity:
              parse_from: attributes.sev
    processors:
    exporters:
      otlp:
        endpoint: filestorageext-collector:4317
        tls:
          insecure: true
    extensions:
      file_storage:
        directory: /filestorageext/data
        timeout: 1s
        compaction:
          on_start: true
          directory: /filestorageext/compaction
          max_transaction_size: 65_536
        fsync: true
    service:
      extensions: [file_storage]
      pipelines:
        logs:
          receivers: [filelog]
          processors: []
          exporters: [otlp]
  volumeMounts:
  - name: log-data
    mountPath: /log-data
  - name: filestorageext
    mountPath: /filestorageext/data
  - name: filestorageext
    mountPath: /filestorageext/compaction
```

### 4. Log Generator Application
The test includes a log generator application that writes logs to files which are then collected by the sidecar collector.

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy main collector with debug exporter and configure namespace RBAC
2. **Create Log Generator App** - Deploy application that generates plaintext logs
3. **Wait for Log Collection** - Allow 10 seconds for logs to be processed
4. **Check Collected Logs** - Verify logs are collected and forwarded to main collector
5. **Confirm File Storage Extension** - Verify file storage extension creates required state files

## 🔍 File Storage Extension Configuration

### Storage Settings:
- **Storage Directory**: `/filestorageext/data`
- **Timeout**: 1 second for storage operations
- **Fsync**: Enabled for data durability and crash consistency

### Compaction Configuration:
- **On Start**: Enabled to optimize storage on collector startup
- **Compaction Directory**: `/filestorageext/compaction`
- **Max Transaction Size**: 65,536 bytes per transaction

### Integration with Filelog Receiver:
- **Storage Reference**: `storage: file_storage`
- **File Pattern**: `/log-data/*.log`
- **State Persistence**: Tracks file read positions across restarts

### Log Processing:
- **Parser**: Regex parser for structured log extraction
- **Timestamp Parsing**: Extracts timestamps from log entries
- **Severity Parsing**: Maps log levels to OpenTelemetry severity

## 🔍 Verification

The test verification includes two checks:

### 1. Log Processing Verification:
Confirms that logs are successfully collected from files and forwarded to the main collector.

### 2. File Storage Extension Verification:
The `check_filestorageext.sh` script verifies that the file storage extension creates state files:
- Checks for `receiver_filelog_` files in `/filestorageext/data`
- Checks for `receiver_filelog_` files in `/filestorageext/compaction`
- Confirms both storage and compaction directories contain the expected state files

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses sidecar deployment pattern for log collection with file storage
- Demonstrates persistent state management for filelog receiver
- Configures both storage and compaction directories for optimal performance
- Enables fsync for data durability in production-like scenarios
- Shows integration between file storage extension and log processing pipeline
- Validates state file creation in both main storage and compaction directories 