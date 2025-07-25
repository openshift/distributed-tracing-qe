# OpenTelemetry FileLog Receiver Test

This test demonstrates the OpenTelemetry FileLog receiver configuration for collecting logs from Kubernetes pods.

## 🎯 What This Test Does

The test validates that the FileLog receiver can:
- Collect logs from all pods in the cluster using a DaemonSet deployment
- Parse container logs using the container operator
- Export collected logs to a debug exporter for verification

## 📋 Test Resources

### 1. SecurityContextConstraints (SCC)
```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: otel-clusterlogs-collector-scc
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
- system:serviceaccount:chainsaw-filelog:clusterlogs-collector
```

### 2. OpenTelemetry Collector
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: clusterlogs
  namespace: chainsaw-filelog
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: daemonset
  config:
    receivers:
      filelog:
        include:
        - /var/log/pods/*/*/*.log
        exclude:
        - /var/log/pods/*/otc-container/*.log
        - "/var/log/pods/*/*/*.gz"
        - "/var/log/pods/*/*/*.log.*"
        - "/var/log/pods/*/*/*.tmp"
        - "/var/log/pods/default_*/*/*.log"
        - "/var/log/pods/kube-*_*/*/*.log"
        - "/var/log/pods/kube_*/*/*.log"
        - "/var/log/pods/openshift-*_*/*/*.log"
        - "/var/log/pods/openshift_*/*/*.log"
        include_file_path: true
        include_file_name: false
        operators:
        - type: container
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        logs:
          receivers: [filelog]
          exporters: [debug]
  securityContext:
    runAsUser: 0
    seLinuxOptions:
      type: spc_t
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    seccompProfile:
      type: RuntimeDefault
    capabilities:
      drop:
      - ALL
  volumeMounts:
  - name: varlogpods
    mountPath: /var/log/pods
    readOnly: true
  volumes:
  - name: varlogpods
    hostPath:
      path: /var/log/pods
```

### 3. Test Application (Log Generator)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-log-plaintext-config
data:
  ocp_logtest.cfg: --rate 60.0

---
apiVersion: v1
kind: ReplicationController
metadata:
  labels:
    run: otel-logtest-plaintext
    test: otel-logtest-plaintext
  name: app-log-plaintext-rc
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
      - env: []
        image: quay.io/openshifttest/ocp-logtest@sha256:6e2973d7d454ce412ad90e99ce584bf221866953da42858c4629873e53778606
        imagePullPolicy: IfNotPresent
        name: app-log-plaintext
        resources: {}
        terminationMessagePath: /dev/termination-log
        volumeMounts:
        - mountPath: /var/lib/svt
          name: config
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      volumes:
      - configMap:
          name: app-log-plaintext-config
        name: config
```

## 🚀 Test Steps

1. **Create OpenTelemetry Collector** - Deploy the collector with FileLog receiver
2. **Create Test Application** - Deploy a log-generating application
3. **Verify Log Collection** - Check that logs are being collected and processed

## 🔍 Verification

The test verification script checks for these log indicators:
- `log.file.path` - File path is included in logs
- `SVTLogger` - Application log content
- `Body: Str(.*SVTLogger.*app-log-plaintext-` - Structured log format
- `k8s.container.name: Str(app-log-plaintext)` - Container name attribute
- `k8s.namespace.name: Str(chainsaw-filelog)` - Namespace attribute

## 🧹 Cleanup

The test runs in the `chainsaw-filelog` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses DaemonSet mode to collect logs from all nodes
- Excludes system namespaces (kube-*, openshift-*, default)
- Includes file path and uses container operator for parsing
- Runs with minimal privileges using SecurityContextConstraints
- Mounts `/var/log/pods` as read-only from the host 