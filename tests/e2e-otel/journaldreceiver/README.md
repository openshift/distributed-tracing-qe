# OpenTelemetry Journald Receiver Test

This test demonstrates the OpenTelemetry Journald receiver configuration for collecting systemd journal logs.

## 🎯 What This Test Does

The test validates that the Journald receiver can:
- Collect systemd journal logs from host system
- Access journal files with privileged permissions
- Export collected journal logs to a debug exporter for verification

## 📋 Test Resources

### 1. Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: chainsaw-journald
  labels:
    security.openshift.io/scc.podSecurityLabelSync: "false"
    pod-security.kubernetes.io/enforce: "privileged"
    pod-security.kubernetes.io/audit: "privileged"
    pod-security.kubernetes.io/warn: "privileged"
```

### 2. ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: privileged-sa
  namespace: chainsaw-journald
```

### 3. ClusterRoleBinding
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: chainsaw-journald--binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:openshift:scc:privileged
subjects:
- kind: ServiceAccount
  name: privileged-sa
  namespace: chainsaw-journald
```

### 4. OpenTelemetry Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-joural-logs
  namespace: chainsaw-journald
spec:
  mode: daemonset
  image: registry.redhat.io/rhosdt/opentelemetry-collector-rhel8:latest
  serviceAccount: privileged-sa
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
      - CHOWN
      - DAC_OVERRIDE
      - FOWNER
      - FSETID
      - KILL
      - NET_BIND_SERVICE
      - SETGID
      - SETPCAP
      - SETUID
    readOnlyRootFilesystem: true
    seLinuxOptions:
      type: spc_t
    seccompProfile:
      type: RuntimeDefault
  config: |
    receivers:
      journald:
        files: /var/log/journal/*/*
        units:
          - kubelet.service
          - crio.service
    processors:
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        logs:
          receivers: [journald]
          processors: []
          exporters: [debug]
  volumeMounts:
  - name: journal-logs
    mountPath: /var/log/journal/
    readOnly: true
  volumes:
  - name: journal-logs
    hostPath:
      path: /var/log/journal
  tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
```

## 🚀 Test Steps

1. **Create OpenTelemetry Collector** - Deploy the collector with Journald receiver
2. **Wait for Log Collection** - Allow 60 seconds for journal logs to be collected
3. **Verify Log Collection** - Check that expected systemd journal logs are being collected

## 🔍 Verification

The test verification script checks for these specific journal log fields:
- `_SYSTEMD_UNIT` - Systemd unit information
- `_UID` - User ID
- `_HOSTNAME` - Hostname
- `_SYSTEMD_INVOCATION_ID` - Systemd invocation ID
- `_SELINUX_CONTEXT` - SELinux context

## 🧹 Cleanup

The test runs in the `chainsaw-journald` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses DaemonSet mode to collect journal logs from all nodes
- Requires privileged security context and special SELinux type (spc_t)
- Uses Red Hat OpenShift Distributed Tracing collector image
- Mounts host journal directory (`/var/log/journal`) as read-only
- Filters logs to specific systemd units: kubelet.service and crio.service
- Drops most capabilities for security while maintaining necessary access
- Tolerates master node taints for comprehensive coverage
- Requires privileged SCC (Security Context Constraint) in OpenShift 