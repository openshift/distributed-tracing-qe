# AWS X-Ray Exporter - Distributed Tracing to AWS

This blueprint demonstrates how to use the OpenTelemetry AWS X-Ray exporter to send distributed traces from your Kubernetes applications to AWS X-Ray for analysis and monitoring. This enables comprehensive distributed tracing across your microservices architecture.

## 🎯 Use Case

- **Distributed Tracing**: Track requests across multiple microservices
- **AWS Cloud Integration**: Leverage AWS X-Ray for trace analysis and service maps
- **Performance Monitoring**: Identify bottlenecks and optimize application performance
- **Service Dependency Mapping**: Visualize service interactions and dependencies
- **Error Analysis**: Debug issues across distributed systems

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with AWS X-Ray exporter
- **AWS Credentials Secret**: Secure storage for AWS authentication
- **HotROD Application**: Sample microservices app that generates traces
- **Trace Generator**: Creates sample distributed traces for testing

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- **AWS Account** with X-Ray service access
- **AWS Credentials** with X-Ray write permissions
- `aws` CLI tool (optional, for verification)

### Step 1: Set Up AWS Credentials

Create AWS credentials with the following permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "xray:PutTraceSegments",
                "xray:PutTelemetryRecords",
                "xray:GetSamplingRules",
                "xray:GetSamplingTargets",
                "xray:GetTraceSummaries"
            ],
            "Resource": "*"
        }
    ]
}
```

### Step 2: Create Namespace and AWS Secret

```bash
# Create dedicated namespace for testing
kubectl create namespace awsxray-demo

# Set as current namespace
kubectl config set-context --current --namespace=awsxray-demo

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
NAMESPACE=awsxray-demo ./create-aws-creds-secret.sh
```

**Method 3: From AWS CLI configuration**
```bash
kubectl create secret generic aws-credentials \
  --from-literal=access_key_id=$(aws configure get aws_access_key_id) \
  --from-literal=secret_access_key=$(aws configure get aws_secret_access_key)
```

### Step 3: Deploy OpenTelemetry Collector with X-Ray Exporter

Create the collector configuration:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: xray
  namespace: awsxray-demo
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
      # OTLP receiver for traces from applications
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
        send_batch_size: 512
      
      # Memory limiter to prevent OOM
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 15
      
      # Resource processor to add metadata
      resource:
        attributes:
        - key: service.name
          value: "otel-xray-demo"
          action: upsert
        - key: deployment.environment
          value: "demo"
          action: upsert

    exporters:
      # AWS X-Ray exporter configuration
      awsxray:
        # Number of concurrent workers
        num_workers: 2
        
        # AWS X-Ray endpoint (adjust region as needed)
        endpoint: "https://xray.us-east-2.amazonaws.com"
        
        # Timeout and retry configuration
        request_timeout_seconds: 30
        max_retries: 2
        no_verify_ssl: false
        
        # AWS region
        region: "us-east-2"
        
        # X-Ray specific settings
        local_mode: false
        index_all_attributes: false
        
        # Optional: AWS log groups for enhanced functionality
        aws_log_groups: ["xray-demo=tracing-test"]
        
        # Telemetry configuration
        telemetry:
          enabled: true
          include_metadata: true
          hostname: "ocp-otel-collector"
          instance_id: "otel-collector-xray"
      
      # Debug exporter for troubleshooting
      debug:
        verbosity: basic

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, resource, batch]
          exporters: [awsxray, debug]
      
      # Telemetry configuration
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

### Step 4: Deploy HotROD Sample Application

Create the HotROD application that generates distributed traces:

```yaml
# install-hotrod.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hotrod
  namespace: awsxray-demo
  labels:
    app: hotrod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hotrod
  template:
    metadata:
      labels:
        app: hotrod
    spec:
      containers:
      - name: hotrod
        image: quay.io/jaegertracing/example-hotrod-snapshot:latest
        args:
        - all
        - --otel-exporter=otlp
        ports:
        - containerPort: 8080
        env:
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: http://xray-collector:4318
        - name: OTEL_SERVICE_NAME
          value: hotrod
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "service.name=hotrod,service.version=1.0.0"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: hotrod
  namespace: awsxray-demo
spec:
  selector:
    app: hotrod
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: ClusterIP
```

Apply the application:

```bash
kubectl apply -f install-hotrod.yaml

# Wait for the application to be ready
kubectl wait --for=condition=available deployment/hotrod --timeout=300s
```

### Step 5: Generate Traces

Create a job to generate sample traces:

```yaml
# generate-traces.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces
  namespace: awsxray-demo
spec:
  template:
    spec:
      containers:
      - name: trace-generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          echo "Generating traces for 2 minutes..."
          end_time=$(($(date +%s) + 120))
          
          while [ $(date +%s) -lt $end_time ]; do
            # Generate different types of requests
            curl -s http://hotrod/dispatch?customer=392&nonse=0.17041766277477502 || true
            curl -s http://hotrod/dispatch?customer=392&nonse=0.17041766277477502 || true
            curl -s http://hotrod/dispatch?customer=731&nonse=0.4288183028582655 || true
            curl -s http://hotrod/dispatch?customer=567&nonse=0.23543899261045138 || true
            curl -s http://hotrod/dispatch?customer=392&nonse=0.17041766277477502 || true
            curl -s http://hotrod/dispatch?customer=731&nonse=0.4288183028582655 || true
            
            # Add some delay between requests
            sleep 1
          done
          
          echo "Trace generation completed"
      restartPolicy: Never
  backoffLimit: 3
```

Apply the trace generator:

```bash
kubectl apply -f generate-traces.yaml

# Monitor the job
kubectl logs job/generate-traces -f
```

### Step 6: Verify Traces in AWS X-Ray

Check that traces are being sent to AWS X-Ray:

```bash
# Check collector logs for successful exports
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector --tail=50

# Use AWS CLI to verify traces (if available)
aws xray get-trace-summaries \
  --start-time $(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --region us-east-2
```

**Verification Script:**
```bash
# Create verification script
cat > check_traces.sh << 'EOF'
#!/bin/bash
set -e

region="us-east-2"

# Check if AWS credentials are available
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "AWS credentials not found in environment"
    exit 1
fi

export AWS_DEFAULT_REGION=${region}

echo "Checking for traces in AWS X-Ray..."

# Query traces from the last 10 minutes
output=$(aws xray get-trace-summaries \
    --start-time $(date -u -d '10 minutes ago' '+%Y-%m-%dT%H:%M:%S') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
    --filter-expression 'service(id(name: "customer"))' \
    --no-cli-pager)

# Check if traces were found
if echo "$output" | jq -e '.TraceSummaries | length > 0' > /dev/null; then
    trace_count=$(echo "$output" | jq '.TraceSummaries | length')
    echo "✓ Found $trace_count traces in AWS X-Ray"
    
    # Show service statistics
    echo "Service statistics:"
    echo "$output" | jq '.TraceSummaries[0].ServiceIds[]?' | head -5
else
    echo "✗ No traces found in AWS X-Ray"
    exit 1
fi

echo "Trace verification completed successfully!"
EOF

chmod +x check_traces.sh
./check_traces.sh
```

### Step 7: View Traces in AWS Console

1. **Open AWS X-Ray Console**: Navigate to AWS X-Ray in the AWS Console
2. **Select Region**: Ensure you're in the correct region (us-east-2 by default)
3. **View Service Map**: See the distributed service map showing:
   - `hotrod` service
   - `customer` service
   - `driver` service
   - `route` service
4. **Analyze Traces**: Click on traces to see detailed timing and error information

## 🔧 Advanced Configuration

### Multi-Region Setup

For multi-region deployments:

```yaml
exporters:
  awsxray/us-east-1:
    endpoint: "https://xray.us-east-1.amazonaws.com"
    region: "us-east-1"
  awsxray/us-west-2:
    endpoint: "https://xray.us-west-2.amazonaws.com"
    region: "us-west-2"

service:
  pipelines:
    traces/east:
      receivers: [otlp]
      processors: [batch]
      exporters: [awsxray/us-east-1]
    traces/west:
      receivers: [otlp]
      processors: [batch]
      exporters: [awsxray/us-west-2]
```

### Custom Sampling Rules

Configure sampling to reduce costs:

```yaml
processors:
  probabilistic_sampler:
    sampling_percentage: 10  # Sample 10% of traces
```

### Resource Attribution

Add custom resource attributes:

```yaml
processors:
  resource:
    attributes:
    - key: aws.region
      value: "us-east-2"
      action: upsert
    - key: k8s.cluster.name
      value: "my-cluster"
      action: upsert
    - key: environment
      value: "production"
      action: upsert
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check collector status
kubectl get opentelemetrycollector xray

# Check pod status
kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector

# Check service endpoints
kubectl get svc -l app.kubernetes.io/component=opentelemetry-collector
```

### Common Issues

**Issue: Authentication Failed**
```bash
# Check AWS credentials
kubectl get secret aws-credentials -o yaml

# Verify credentials are correct
kubectl exec deployment/xray-collector -- env | grep AWS
```

**Issue: No Traces in X-Ray**
```bash
# Check collector logs for errors
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector | grep -i error

# Verify OTLP endpoint connectivity
kubectl exec deployment/hotrod -- curl -v http://xray-collector:4318/v1/traces
```

**Issue: High Memory Usage**
```bash
# Check memory usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Adjust memory limiter
kubectl patch opentelemetrycollector xray --type='merge' -p='{"spec":{"config":"processors:\n  memory_limiter:\n    limit_percentage: 50"}}'
```

## 🔐 Security Considerations

1. **AWS IAM Permissions**: Use minimal required permissions
2. **Credential Rotation**: Regularly rotate AWS access keys
3. **Network Policies**: Restrict collector network access
4. **Resource Limits**: Set appropriate CPU and memory limits

```yaml
# Example security-enhanced configuration
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    fsGroup: 65534
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi
```

## 📊 Cost Optimization

### Sampling Strategies

```yaml
# Tail-based sampling to reduce costs
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: slow
        type: latency
        latency: {threshold_ms: 1000}
      - name: random
        type: probabilistic
        probabilistic: {sampling_percentage: 1}
```

### Batch Configuration

```yaml
processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
    send_batch_max_size: 2048
```

## 📚 Related Patterns

- [tailsamplingprocessor](../tailsamplingprocessor/) - For intelligent trace sampling
- [loadbalancingexporter](../loadbalancingexporter/) - For high-availability setups
- [routingconnector](../routingconnector/) - For conditional trace routing

## 🧹 Cleanup

```bash
# Remove trace generator job
kubectl delete job generate-traces

# Remove HotROD application
kubectl delete deployment hotrod
kubectl delete service hotrod

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector xray

# Remove AWS credentials secret
kubectl delete secret aws-credentials

# Remove namespace
kubectl delete namespace awsxray-demo
```

## 📖 Additional Resources

- [AWS X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [OpenTelemetry AWS X-Ray Exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/awsxrayexporter)
- [HotROD Demo Application](https://github.com/jaegertracing/jaeger/tree/main/examples/hotrod) 