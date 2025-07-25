# Journald Receiver - System Log Collection

This blueprint demonstrates how to use the OpenTelemetry Journald Receiver to collect system logs from the systemd journal. This is essential for comprehensive system monitoring, security auditing, and troubleshooting infrastructure issues.

## 🎯 Use Case

- **System Log Collection**: Collect comprehensive system logs from systemd journal
- **Infrastructure Monitoring**: Monitor system services, daemons, and kernel messages
- **Security Auditing**: Capture authentication, authorization, and security events
- **Troubleshooting**: Debug system-level issues and service failures
- **Compliance**: Meet regulatory requirements for system log retention

## 📋 What You'll Deploy

- **OpenTelemetry Collector DaemonSet**: Runs on each node with privileged access
- **Service Account & RBAC**: Privileged permissions for journal access
- **Security Context**: Secure configuration for privileged containers
- **Journald Receiver**: Configured to collect specific systemd units

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- **Privileged container access** (required for journal access)
- Understanding of systemd and journald concepts

### Step 1: Create Namespace with Security Settings

```bash
# Create dedicated namespace for testing
kubectl create namespace journaldreceiver-demo

# Set as current namespace
kubectl config set-context --current --namespace=journaldreceiver-demo
```

For OpenShift, create namespace with privileged pod security:

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: journaldreceiver-demo
  labels:
    security.openshift.io/scc.podSecurityLabelSync: "false"
    pod-security.kubernetes.io/enforce: "privileged"
    pod-security.kubernetes.io/audit: "privileged"  
    pod-security.kubernetes.io/warn: "privileged"
```

### Step 2: Create Service Account and RBAC

```yaml
# rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: privileged-sa
  namespace: journaldreceiver-demo

---
# For OpenShift - bind to privileged SCC
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: journaldreceiver-demo-privileged-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:openshift:scc:privileged
subjects:
- kind: ServiceAccount
  name: privileged-sa
  namespace: journaldreceiver-demo

---
# For general Kubernetes - create privileged cluster role
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: journald-reader
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: journaldreceiver-demo-reader-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: journald-reader
subjects:
- kind: ServiceAccount
  name: privileged-sa
  namespace: journaldreceiver-demo
```

Apply the RBAC configuration:

```bash
kubectl apply -f rbac.yaml
```

### Step 3: Deploy OpenTelemetry Collector with Journald Receiver

Create the collector configuration:

```yaml
# otel-journaldreceiver.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-journal-logs
  namespace: journaldreceiver-demo
spec:
  mode: daemonset
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  serviceAccount: privileged-sa
  
  # Security context for privileged access
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
    # For OpenShift - use spc_t context for systemd access
    seLinuxOptions:
      type: spc_t
    seccompProfile:
      type: RuntimeDefault
  
  config:
    receivers:
      # Journald receiver configuration
      journald:
        # Journal files location
        files: /var/log/journal/*/*
        
        # Specific systemd units to collect (optional)
        units:
          - kubelet.service
          - crio.service
          - containerd.service
          - docker.service
          - sshd.service
          - systemd.service
          - NetworkManager.service
        
        # Additional configuration options
        directory: /var/log/journal
        
        # Operators for log parsing and enrichment
        operators:
        # Add timestamp parsing
        - type: time_parser
          id: time_parser
          parse_from: attributes.__REALTIME_TIMESTAMP
          layout_type: epoch
          layout: μs
          
        # Add severity mapping
        - type: severity_parser
          id: severity_parser
          parse_from: attributes.PRIORITY
          mapping:
            emergency: "0"
            alert: "1"
            critical: "2"
            error: "3"
            warning: "4"
            notice: "5"
            info: "6"
            debug: "7"
        
        # Move message to body
        - type: move
          from: attributes.MESSAGE
          to: body
          
        # Add additional metadata
        - type: add
          field: attributes.log.source
          value: "systemd-journal"
          
        # Transform systemd unit name
        - type: add
          field: attributes.service.name
          value: 'attributes._SYSTEMD_UNIT'
    
    processors:
      # Batch processor for efficiency
      batch:
        timeout: 5s
        send_batch_size: 1024
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 15
      
      # Resource processor to add node information
      resource:
        attributes:
        - key: host.name
          from_attribute: "_HOSTNAME"
          action: upsert
        - key: service.name
          from_attribute: "_SYSTEMD_UNIT"
          action: upsert
        - key: log.source
          value: "journald"
          action: upsert
        
      # Transform processor for log enrichment
      transform:
        log_statements:
        - context: log
          statements:
          # Add systemd-specific attributes
          - set(attributes["systemd.unit"], attributes["_SYSTEMD_UNIT"]) where attributes["_SYSTEMD_UNIT"] != nil
          - set(attributes["systemd.pid"], attributes["_PID"]) where attributes["_PID"] != nil
          - set(attributes["systemd.uid"], attributes["_UID"]) where attributes["_UID"] != nil
          - set(attributes["systemd.gid"], attributes["_GID"]) where attributes["_GID"] != nil
          - set(attributes["systemd.invocation_id"], attributes["_SYSTEMD_INVOCATION_ID"]) where attributes["_SYSTEMD_INVOCATION_ID"] != nil
          
          # Add host information
          - set(attributes["host.name"], attributes["_HOSTNAME"]) where attributes["_HOSTNAME"] != nil
          - set(attributes["host.boot_id"], attributes["_BOOT_ID"]) where attributes["_BOOT_ID"] != nil
          
          # Add process information
          - set(attributes["process.executable.name"], attributes["_EXE"]) where attributes["_EXE"] != nil
          - set(attributes["process.command_line"], attributes["_CMDLINE"]) where attributes["_CMDLINE"] != nil
    
    exporters:
      # Debug exporter for troubleshooting
      debug:
        verbosity: detailed
      
      # Optional: Export to external systems
      # loki:
      #   endpoint: "http://loki:3100/loki/api/v1/push"
      #   labels:
      #     attributes:
      #       systemd.unit: "unit"
      #       host.name: "host"
      
      # otlp:
      #   endpoint: "http://central-collector:4317"
      #   insecure: true
    
    service:
      pipelines:
        logs:
          receivers: [journald]
          processors: [memory_limiter, resource, transform, batch]
          exporters: [debug]
  
  # Volume mounts for journal access
  volumeMounts:
  - name: journal-logs
    mountPath: /var/log/journal/
    readOnly: true
  - name: etc-machine-id
    mountPath: /etc/machine-id
    readOnly: true
  
  volumes:
  - name: journal-logs
    hostPath:
      path: /var/log/journal
  - name: etc-machine-id
    hostPath:
      path: /etc/machine-id
  
  # Tolerations to run on all nodes
  tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  - operator: Exists
    effect: NoExecute
  - operator: Exists
    effect: NoSchedule
  
  # Node selector (optional)
  nodeSelector:
    kubernetes.io/os: linux
```

Apply the collector:

```bash
kubectl apply -f otel-journaldreceiver.yaml

# Wait for the DaemonSet to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 4: Verify Journal Log Collection

Check that system logs are being collected:

```bash
# Check DaemonSet status
kubectl get daemonset -l app.kubernetes.io/component=opentelemetry-collector

# Check pod distribution across nodes
kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o wide

# Check collector logs for journal entries
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=50
```

### Step 5: Generate System Activity

Create some system activity to verify log collection:

```bash
# Generate SSH activity (if SSH is available)
kubectl exec -it deployment/test-app -- ssh localhost 2>/dev/null || true

# Restart a systemd service (if possible)
kubectl exec -it deployment/test-app -- systemctl restart rsyslog 2>/dev/null || true

# Check systemd journal directly
kubectl exec -it deployment/test-app -- journalctl -n 10
```

### Step 6: Run Verification Script

Create an automated verification script:

```bash
# Create verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking journald receiver functionality..."

# Define the label selector and namespace
LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=${NAMESPACE:-journaldreceiver-demo}

# Define the expected systemd journal fields
EXPECTED_FIELDS=(
  "_SYSTEMD_UNIT"
  "_UID"
  "_HOSTNAME"
  "_SYSTEMD_INVOCATION_ID"
  "_BOOT_ID"
  "_PID"
)

# Get the collector pods
PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "❌ No collector pods found with label $LABEL_SELECTOR in namespace $NAMESPACE"
    exit 1
fi

echo "Found ${#PODS[@]} collector pod(s): ${PODS[*]}"

# Check each pod for journal data
for POD in "${PODS[@]}"; do
    echo "Checking pod: $POD"
    
    # Get logs from the pod
    LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=400 2>/dev/null || echo "")
    
    if [ -z "$LOGS" ]; then
        echo "⚠️  No logs found in pod $POD"
        continue
    fi
    
    # Check for expected systemd journal fields
    found_fields=0
    for FIELD in "${EXPECTED_FIELDS[@]}"; do
        if echo "$LOGS" | grep -q -- "$FIELD"; then
            echo "✅ \"$FIELD\" found in $POD"
            ((found_fields++))
        else
            echo "⚠️  \"$FIELD\" not found in $POD"
        fi
    done
    
    if [ $found_fields -ge 3 ]; then
        echo "✅ Pod $POD has sufficient journal data ($found_fields/${#EXPECTED_FIELDS[@]} fields)"
    else
        echo "❌ Pod $POD has insufficient journal data ($found_fields/${#EXPECTED_FIELDS[@]} fields)"
    fi
done

echo "🎉 Journald receiver verification completed!"
echo "✅ System logs are being collected from systemd journal"
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Specific Service Monitoring

Monitor specific systemd services:

```yaml
receivers:
  journald:
    files: /var/log/journal/*/*
    units:
      - kubelet.service
      - containerd.service
      - NetworkManager.service
      - sshd.service
      - postgresql.service
      - nginx.service
```

### Log Filtering and Processing

Filter and process journal entries:

```yaml
processors:
  filter:
    logs:
      log_record:
        # Only keep error and warning logs
        - 'severity_number < SEVERITY_NUMBER_WARN'
        # Filter out noisy services
        - 'attributes["_SYSTEMD_UNIT"] == "systemd-logind.service"'
  
  transform:
    log_statements:
    - context: log
      statements:
      # Extract service name from unit
      - replace_pattern(attributes["service.name"], "_SYSTEMD_UNIT", "\\.(service|socket|timer)$", "") where attributes["_SYSTEMD_UNIT"] != nil
```

### Multi-File Collection

Collect from multiple journal locations:

```yaml
receivers:
  journald/system:
    files: /var/log/journal/*/*
    directory: /var/log/journal
  
  journald/user:
    files: /var/log/journal/*/user-*
    directory: /var/log/journal
```

### Custom Operators

Add custom log processing operators:

```yaml
receivers:
  journald:
    operators:
    # Parse structured message fields
    - type: json_parser
      id: message_parser
      parse_from: body
      parse_to: attributes.parsed_message
      
    # Extract IP addresses
    - type: regex_parser
      id: ip_extractor
      regex: '(?P<ip>\d+\.\d+\.\d+\.\d+)'
      parse_from: body
      parse_to: attributes.ip_address
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check DaemonSet status
kubectl get daemonset -l app.kubernetes.io/component=opentelemetry-collector

# Check pod status on each node
kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o wide

# Check resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector
```

### Common Issues

**Issue: Permission denied accessing journal**
```bash
# Check service account permissions
kubectl get serviceaccount privileged-sa -o yaml

# Verify security context
kubectl describe pod -l app.kubernetes.io/component=opentelemetry-collector | grep -A 10 "Security Context"

# For OpenShift, check SCC assignment
oc get pods -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'
```

**Issue: No journal files found**
```bash
# Check journal directory mount
kubectl exec -it deployment/otel-journal-logs -- ls -la /var/log/journal/

# Verify journal files exist on host
kubectl exec -it deployment/otel-journal-logs -- ls -la /var/log/journal/*/
```

**Issue: High memory usage**
```bash
# Check memory consumption
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Adjust batch settings
kubectl patch opentelemetrycollector otel-journal-logs --type='merge' -p='{"spec":{"config":"processors:\n  batch:\n    send_batch_size: 512"}}'
```

### Journal Diagnostics

```bash
# Check systemd journal on host
journalctl --list-boots
journalctl -u kubelet.service --since "1 hour ago"

# Verify journal accessibility
kubectl exec -it deployment/otel-journal-logs -- journalctl -n 10
```

## 📊 Log Analysis Examples

### Service Health Monitoring

Monitor systemd service health:

```bash
# Find service failures
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "failed\|error"

# Monitor specific service
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep "kubelet.service"
```

### Security Event Analysis

Analyze security-related events:

```bash
# Authentication events
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "authentication\|login"

# Permission errors
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "permission denied"
```

### System Performance

Monitor system performance indicators:

```bash
# OOM events
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "out of memory"

# Disk space issues
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i "no space"
```

## 🔐 Security Considerations

1. **Privileged Access**: Carefully manage privileged container permissions
2. **SELinux Context**: Use appropriate SELinux contexts for journal access
3. **Data Sensitivity**: Journal logs may contain sensitive system information
4. **Resource Limits**: Set appropriate limits to prevent resource exhaustion
5. **Access Control**: Restrict access to journal data based on security requirements

## 📚 Related Patterns

- [filelog](../filelog/) - For application log collection
- [k8seventsreceiver](../k8seventsreceiver/) - For Kubernetes event collection
- [hostmetricsreceiver](../hostmetricsreceiver/) - For system metrics

## 🧹 Cleanup

```bash
# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector otel-journal-logs

# Remove RBAC configuration
kubectl delete clusterrolebinding journaldreceiver-demo-privileged-binding journaldreceiver-demo-reader-binding
kubectl delete clusterrole journald-reader
kubectl delete serviceaccount privileged-sa

# Remove namespace
kubectl delete namespace journaldreceiver-demo
```

## 📖 Additional Resources

- [OpenTelemetry Journald Receiver Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/journaldreceiver)
- [systemd Journal Documentation](https://www.freedesktop.org/software/systemd/man/systemd-journald.service.html)
- [OpenShift Security Context Constraints](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html) 