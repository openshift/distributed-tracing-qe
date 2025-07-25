# AWS CloudWatch Logs Exporter - Centralized Log Aggregation

This blueprint demonstrates how to use the OpenTelemetry AWS CloudWatch Logs exporter to send application logs and metrics to AWS CloudWatch for centralized monitoring and analysis. This includes both direct log export and Enhanced Monitoring Format (EMF) for metrics.

## 🎯 Use Case

- **Centralized Logging**: Aggregate application logs in AWS CloudWatch Logs
- **AWS Cloud Integration**: Leverage AWS native logging and monitoring services
- **Log Retention Management**: Automated log retention and lifecycle management
- **Metrics and Logs Correlation**: Combine structured logging with custom metrics
- **Operational Insights**: Use CloudWatch dashboards and alarms for monitoring

## 📋 What You'll Deploy

- **Primary OpenTelemetry Collector**: Configured with AWS CloudWatch exporters
- **Sidecar Collector**: File log collection with OTLP forwarding
- **AWS Credentials Secret**: Secure storage for AWS authentication
- **Log Generator Application**: Sample app that writes logs to files
- **Metrics Generator**: Creates custom metrics for AWS EMF export

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- **AWS Account** with CloudWatch access
- **AWS Credentials** with CloudWatch Logs permissions
- `aws` CLI tool (for verification)

### Step 1: Set Up AWS Credentials

Create AWS credentials with the following permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:GetLogEvents",
                "logs:DeleteLogGroup",
                "cloudwatch:PutMetricData",
                "cloudwatch:ListMetrics"
            ],
            "Resource": "*"
        }
    ]
}
```

### Step 2: Create Namespace and AWS Secret

```bash
# Create dedicated namespace for testing
kubectl create namespace awscloudwatchlogs-demo

# Set as current namespace
kubectl config set-context --current --namespace=awscloudwatchlogs-demo

# Create AWS credentials secret (choose one method below)
```

**Method 1: Manual Secret Creation**
```bash
kubectl create secret generic aws-credentials \
  --from-literal=access_key_id=YOUR_ACCESS_KEY_ID \
  --from-literal=secret_access_key=YOUR_SECRET_ACCESS_KEY
```

**Method 2: Using the provided script**
```bash
# If you have CLUSTER_PROFILE_DIR set or aws-creds secret in kube-system
NAMESPACE=awscloudwatchlogs-demo ./create-aws-creds-secret.sh
```

**Method 3: From AWS CLI configuration**
```bash
kubectl create secret generic aws-credentials \
  --from-literal=access_key_id=$(aws configure get aws_access_key_id) \
  --from-literal=secret_access_key=$(aws configure get aws_secret_access_key)
```

### Step 3: Deploy Primary OpenTelemetry Collector

Create the main collector with AWS exporters:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: cwlogs
  namespace: awscloudwatchlogs-demo
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  
  # AWS credentials from secret
  env:
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: aws-credentials
        key: access_key_id
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: aws-credentials
        key: secret_access_key
  
  config:
    receivers:
      # OTLP receiver for logs and metrics from sidecar
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
        send_batch_max_size: 2048
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
      
      # Resource processor for metadata
      resource:
        attributes:
        - key: cluster.name
          value: "cloudwatch-demo-cluster"
          action: upsert
        - key: deployment.environment
          value: "demo"
          action: upsert
    
    exporters:
      # Debug exporter for troubleshooting
      debug:
        verbosity: detailed
      
      # AWS CloudWatch Logs exporter
      awscloudwatchlogs:
        log_group_name: "tracing-awscloudwatchlogs-demo"
        log_stream_name: "tracing-awscloudwatchlogs-demo-stream"
        raw_log: true
        region: "us-east-2"
        endpoint: "https://logs.us-east-2.amazonaws.com"
        log_retention: 1  # days
        tags:
          tracing-otel: "true"
          environment: "demo"
      
      # AWS Enhanced Monitoring Format (EMF) exporter for metrics
      awsemf:
        log_group_name: "tracing-awscloudwatchlogs-demo"
        log_stream_name: "tracing-awscloudwatchlogs-demo-stream-emf"
        log_retention: 1
        tags:
          tracing-otel: "true"
          metrics-type: "emf"
        namespace: "Tracing-EMF"
        endpoint: "https://logs.us-east-2.amazonaws.com"
        no_verify_ssl: false
        region: "us-east-2"
        max_retries: 2
        dimension_rollup_option: "ZeroAndSingleDimensionRollup"
        resource_to_telemetry_conversion:
          enabled: true
        output_destination: "cloudwatch"
        detailed_metrics: false
    
    service:
      pipelines:
        # Logs pipeline
        logs:
          receivers: [otlp]
          processors: [memory_limiter, resource, batch]
          exporters: [awscloudwatchlogs, debug]
        
        # Metrics pipeline with EMF export
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, resource, batch]
          exporters: [awsemf, debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

Apply the collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 4: Set Up RBAC for Sidecar (OpenShift)

For OpenShift clusters, configure the necessary permissions:

```bash
# Create role binding for pod view
kubectl create rolebinding default-view-awscloudwatchlogs-demo \
  --role=pod-view \
  --serviceaccount=awscloudwatchlogs-demo:ta

# Set security context annotations
kubectl annotate namespace awscloudwatchlogs-demo \
  openshift.io/sa.scc.uid-range=1000/1000 --overwrite

kubectl annotate namespace awscloudwatchlogs-demo \
  openshift.io/sa.scc.supplemental-groups=3000/1000 --overwrite
```

### Step 5: Deploy Sidecar Collector for File Log Collection

Create a sidecar collector to collect logs from files:

```yaml
# otel-filelog-sidecar.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-logs-sidecar
  namespace: awscloudwatchlogs-demo
spec:
  mode: sidecar
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  
  config:
    receivers:
      # File log receiver for application logs
      filelog:
        include: [/log-data/*.log]
        
        # Log parsing operators
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
          value: "file-logs"
          
        - type: add
          field: attributes.log_type
          value: "application"
    
    processors:
      # Batch processing
      batch:
        timeout: 2s
        send_batch_size: 512
      
      # Resource attributes
      resource:
        attributes:
        - key: service.name
          value: "log-generator-app"
          action: upsert
    
    exporters:
      # Forward to main collector
      otlp:
        endpoint: cwlogs-collector:4317
        tls:
          insecure: true
    
    service:
      pipelines:
        logs:
          receivers: [filelog]
          processors: [resource, batch]
          exporters: [otlp]
  
  # Volume mount for log files
  volumeMounts:
  - name: log-data
    mountPath: /log-data
```

Apply the sidecar collector:

```bash
kubectl apply -f otel-filelog-sidecar.yaml

# Wait for the sidecar collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=opentelemetry-collector --timeout=300s
```

### Step 6: Deploy Log Generator Application

Create an application that generates logs to files:

```yaml
# app-plaintext-logs.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-log-plaintext-config
  namespace: awscloudwatchlogs-demo
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
  namespace: awscloudwatchlogs-demo
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
```

Apply the log generator:

```bash
kubectl apply -f app-plaintext-logs.yaml

# Wait for the replication controller to be ready
kubectl wait --for=condition=ready pod -l run=otel-logtest-plaintext --timeout=300s
```

### Step 7: Generate Sample Metrics

Create a job to generate sample metrics for EMF export:

```yaml
# generate-metrics.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: telemetrygen-metrics
  namespace: awscloudwatchlogs-demo
spec:
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        app: telemetrygen-metrics
    spec:
      containers:
      - name: telemetrygen-metrics
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - "--otlp-endpoint=cwlogs-collector:4317"
        - "--otlp-insecure=true"
        - "--duration=60s"
        - "--rate=5"
        - "--otlp-attributes=telemetrygen=\"metrics\""
        - "--otlp-header=telemetrygen=\"traces\""
        - "metrics"
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

Apply the metrics generator:

```bash
kubectl apply -f generate-metrics.yaml

# Monitor the job
kubectl logs job/telemetrygen-metrics -f
```

### Step 8: Verify CloudWatch Integration

Check that logs and metrics are being sent to AWS CloudWatch:

```bash
# Check collector logs
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=50

# Use AWS CLI to verify log groups
aws logs describe-log-groups --log-group-name-prefix tracing-awscloudwatchlogs-demo --region us-east-2

# Check log streams
aws logs describe-log-streams --log-group-name tracing-awscloudwatchlogs-demo --region us-east-2

# Get sample log events
aws logs get-log-events \
  --log-group-name tracing-awscloudwatchlogs-demo \
  --log-stream-name tracing-awscloudwatchlogs-demo-stream \
  --region us-east-2 \
  --limit 10
```

### Step 9: Run Verification Script

Create an automated verification script:

```bash
# Create verification script
cat > check_logs_metrics.sh << 'EOF'
#!/bin/bash
set -e

region="us-east-2"
log_group_name="tracing-awscloudwatchlogs-demo"
log_stream_name="tracing-awscloudwatchlogs-demo-stream"

# Check if AWS credentials are available
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "AWS credentials not found in environment"
    exit 1
fi

export AWS_DEFAULT_REGION=${region}

echo "Checking AWS CloudWatch Logs and Metrics..."

# Check log retention setting
echo "Verifying log retention..."
RETENTION_DAYS=$(aws logs describe-log-groups \
  --log-group-name-prefix $log_group_name \
  --region $region \
  --query "logGroups[?logGroupName=='$log_group_name'].retentionInDays" \
  --output text)

if [ "$RETENTION_DAYS" == "1" ]; then
    echo "✅ Log retention is set to 1 day"
else
    echo "❌ Log retention is not set to 1 day (found: $RETENTION_DAYS)"
    exit 1
fi

# Check for application logs
echo "Checking for application logs..."
MESSAGE=$(aws logs get-log-events \
  --log-group-name $log_group_name \
  --log-stream-name $log_stream_name \
  --region $region \
  --no-paginate \
  --query "events[0].message" \
  --output text)

if [[ "$MESSAGE" == *"SVTLogger - INFO - app-log-plaintext-rc-"* ]]; then
    echo "✅ Application logs found in CloudWatch Logs"
else
    echo "❌ Application logs not found in CloudWatch Logs"
    echo "Found message: $MESSAGE"
    exit 1
fi

# Check for EMF metrics
echo "Checking for EMF metrics..."
result=$(aws cloudwatch list-metrics \
  --namespace Tracing-EMF \
  --endpoint https://monitoring.us-east-2.amazonaws.com \
  --region=us-east-2 \
  --dimensions Name=telemetrygen,Value=metrics)

if echo "$result" | grep -q '"Name": "telemetrygen",'; then
    echo "✅ EMF metrics found in CloudWatch"
else
    echo "❌ EMF metrics not found in CloudWatch"
    exit 1
fi

echo "🎉 CloudWatch Logs and Metrics verification completed successfully!"
echo "✅ Logs are being exported to CloudWatch Logs"
echo "✅ Metrics are being exported via EMF to CloudWatch"
EOF

chmod +x check_logs_metrics.sh

# Set environment variables and run verification
export AWS_ACCESS_KEY_ID=$(kubectl get secret aws-credentials -o jsonpath='{.data.access_key_id}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(kubectl get secret aws-credentials -o jsonpath='{.data.secret_access_key}' | base64 -d)
./check_logs_metrics.sh
```

### Step 10: View Data in AWS Console

1. **CloudWatch Logs Console**: Navigate to CloudWatch Logs in AWS Console
2. **Log Groups**: Find the `tracing-awscloudwatchlogs-demo` log group
3. **Log Streams**: Browse log streams to see application logs
4. **CloudWatch Metrics**: Navigate to CloudWatch Metrics
5. **Custom Namespace**: Look for `Tracing-EMF` namespace with custom metrics

## 🔧 Advanced Configuration

### Multi-Region Setup

Deploy to multiple AWS regions:

```yaml
exporters:
  awscloudwatchlogs/us-east-1:
    log_group_name: "tracing-east-1"
    region: "us-east-1"
    endpoint: "https://logs.us-east-1.amazonaws.com"
  
  awscloudwatchlogs/us-west-2:
    log_group_name: "tracing-west-2"
    region: "us-west-2"
    endpoint: "https://logs.us-west-2.amazonaws.com"
```

### Custom Log Parsing

Enhanced log parsing for structured logs:

```yaml
receivers:
  filelog:
    operators:
    # Parse JSON logs
    - type: json_parser
      id: json_parser
      parse_from: body
      
    # Extract timestamp
    - type: time_parser
      id: time_parser
      parse_from: attributes.timestamp
      layout: '%Y-%m-%dT%H:%M:%S.%fZ'
      
    # Map severity
    - type: severity_parser
      id: severity_parser
      parse_from: attributes.level
      mapping:
        fatal: 5
        error: 4
        warn: 3
        info: 2
        debug: 1
```

### Conditional Routing

Route different log types to different log groups:

```yaml
processors:
  routing:
    table:
    - statement: route() where attributes["log_type"] == "error"
      pipelines: [logs/errors]
    - statement: route() where attributes["log_type"] == "audit"
      pipelines: [logs/audit]
    default_pipelines: [logs/general]

service:
  pipelines:
    logs/errors:
      receivers: [otlp]
      exporters: [awscloudwatchlogs/errors]
    logs/audit:
      receivers: [otlp]
      exporters: [awscloudwatchlogs/audit]
```

### EMF Custom Dimensions

Add custom dimensions to EMF metrics:

```yaml
exporters:
  awsemf:
    dimension_rollup_option: "ZeroAndSingleDimensionRollup"
    metric_declarations:
    - dimensions: [["service.name"], ["service.name", "deployment.environment"]]
      metric_name_selectors: ["*"]
      namespace: "Custom/Application"
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector status
kubectl get opentelemetrycollector cwlogs

# Check AWS connectivity
aws sts get-caller-identity --region us-east-2

# Test CloudWatch access
aws logs describe-log-groups --region us-east-2 --max-items 5
```

### Common Issues

**Issue: Authentication Failed**
```bash
# Check AWS credentials
kubectl get secret aws-credentials -o yaml

# Test AWS CLI access
aws sts get-caller-identity
```

**Issue: Log Group Creation Failed**
```bash
# Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:user/USERNAME \
  --action-names logs:CreateLogGroup \
  --resource-arns "*"
```

**Issue: Logs Not Appearing**
```bash
# Check sidecar injection
kubectl get pods -o yaml | grep sidecar.opentelemetry.io/inject

# Verify file log collection
kubectl exec -it deployment/app-log-plaintext-rc -- ls -la /log-data/
```

**Issue: High AWS Costs**
```bash
# Adjust log retention
aws logs put-retention-policy \
  --log-group-name tracing-awscloudwatchlogs-demo \
  --retention-in-days 7
```

### Performance Optimization

```bash
# Monitor collector resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Check batch settings
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep batch
```

## 📊 Cost Optimization

### Log Retention Strategies

```yaml
exporters:
  awscloudwatchlogs:
    log_retention: 7  # Reduce retention for cost savings
```

### Selective Log Export

```yaml
processors:
  filter:
    logs:
      log_record:
        # Only export ERROR and WARN logs
        - 'severity_text not in ["ERROR", "WARN"]'
```

### Batch Optimization

```yaml
processors:
  batch:
    timeout: 10s
    send_batch_size: 2048
    send_batch_max_size: 4096
```

## 🔐 Security Considerations

1. **IAM Permissions**: Use minimal required permissions
2. **Credential Rotation**: Regularly rotate AWS access keys
3. **Log Content**: Ensure no sensitive data in logs
4. **Network Security**: Use VPC endpoints for AWS services

## 📚 Related Patterns

- [awsxrayexporter](../awsxrayexporter/) - For distributed tracing to AWS
- [filelog](../filelog/) - For direct log collection
- [prometheusremotewriteexporter](../prometheusremotewriteexporter/) - For metrics export

## 🧹 Cleanup

```bash
# Delete AWS resources first
aws logs delete-log-group --log-group-name tracing-awscloudwatchlogs-demo --region us-east-2

# Remove Kubernetes resources
kubectl delete job telemetrygen-metrics
kubectl delete replicationcontroller app-log-plaintext-rc
kubectl delete configmap app-log-plaintext-config
kubectl delete opentelemetrycollector otel-logs-sidecar cwlogs
kubectl delete secret aws-credentials

# Remove RBAC (OpenShift)
kubectl delete rolebinding default-view-awscloudwatchlogs-demo

# Remove namespace
kubectl delete namespace awscloudwatchlogs-demo
```

## 📖 Additional Resources

- [AWS CloudWatch Logs Exporter Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/awscloudwatchlogsexporter)
- [AWS EMF Exporter Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/awsemfexporter)
- [AWS CloudWatch Logs User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [Enhanced Monitoring Format (EMF)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html) 