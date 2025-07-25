# OpenTelemetry HostMetrics Receiver Test

This test demonstrates the OpenTelemetry HostMetrics receiver configuration for collecting system metrics from Kubernetes nodes.

## 🎯 What This Test Does

The test validates that the HostMetrics receiver can:
- Collect comprehensive system metrics from each node using a DaemonSet deployment
- Access host filesystem for accurate metric collection
- Export collected metrics to a debug exporter for verification

## 📋 Test Resources

### 1. ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-hostfs-daemonset
  namespace: chainsaw-hostmetrics
```

### 2. SecurityContextConstraints (SCC)
```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
allowHostDirVolumePlugin: true
allowHostIPC: false
allowHostNetwork: false
allowHostPID: true
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: true
allowedCapabilities: null
defaultAddCapabilities:
- SYS_ADMIN
fsGroup:
  type: RunAsAny
groups: []
metadata:
  name: otel-hostmetrics
readOnlyRootFilesystem: true
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
users:
- system:serviceaccount:chainsaw-hostmetrics:otel-hostfs-daemonset
volumes:
- configMap
- emptyDir
- hostPath
- projected
```

### 3. OpenTelemetry Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-hstmtrs
spec:
  mode: daemonset
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: otel-hostfs-daemonset
  config: |
    receivers:
      hostmetrics:
        root_path: /hostfs
        collection_interval: 10s
        scrapers:
          cpu:
          load:
          memory:
          disk:
          filesystem:
          network:
          paging:
          processes:
          process:
    processors:
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        metrics:
          receivers: [hostmetrics]
          processors: []
          exporters: [debug]
  volumeMounts:
  - name: hostfs
    mountPath: /hostfs
    readOnly: true
    mountPropagation: HostToContainer
  volumes:
  - name: hostfs
    hostPath:
      path: /
  tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
```

## 🚀 Test Steps

1. **Create OpenTelemetry Collector** - Deploy the collector with HostMetrics receiver
2. **Wait for Metrics Collection** - Allow 60 seconds for metrics to be collected
3. **Verify Metrics Collection** - Check that expected metrics are being collected

## 🔍 Verification

The test verification script checks for these specific metrics:

**Process Metrics:**
- `process.pid` - Process ID
- `process.parent_pid` - Parent process ID
- `process.executable.name` - Executable name
- `process.executable.path` - Executable path
- `process.command` - Command line
- `process.cpu.time` - Process CPU time
- `process.disk.io` - Process disk I/O
- `process.memory.usage` - Process memory usage
- `process.memory.virtual` - Process virtual memory

**System CPU Metrics:**
- `system.cpu.load_average.1m` - 1-minute load average
- `system.cpu.load_average.5m` - 5-minute load average
- `system.cpu.load_average.15m` - 15-minute load average
- `system.cpu.time` - CPU time

**System Disk Metrics:**
- `system.disk.io` - Disk I/O bytes
- `system.disk.io_time` - Disk I/O time
- `system.disk.merged` - Merged disk operations
- `system.disk.operation_time` - Disk operation time
- `system.disk.operations` - Disk operations count
- `system.disk.pending_operations` - Pending disk operations
- `system.disk.weighted_io_time` - Weighted I/O time

**System Filesystem Metrics:**
- `system.filesystem.inodes.usage` - Inode usage
- `system.filesystem.usage` - Filesystem usage

**System Memory Metrics:**
- `system.memory.usage` - Memory usage

**System Network Metrics:**
- `system.network.connections` - Network connections
- `system.network.dropped` - Dropped packets
- `system.network.errors` - Network errors
- `system.network.io` - Network I/O bytes
- `system.network.packets` - Network packets

**System Paging Metrics:**
- `system.paging.faults` - Page faults
- `system.paging.operations` - Paging operations

**System Process Metrics:**
- `system.processes.count` - Process count
- `system.processes.created` - Processes created

## 🧹 Cleanup

The test runs in the `chainsaw-hostmetrics` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses DaemonSet mode to collect metrics from all nodes
- Mounts entire host filesystem at `/hostfs` for accurate metric collection
- Requires privileged access and SYS_ADMIN capability
- Collects metrics every 10 seconds from all available scrapers
- Tolerates master node taints for comprehensive coverage
- Uses read-only host filesystem mount with HostToContainer propagation 