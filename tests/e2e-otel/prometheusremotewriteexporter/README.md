# Prometheus Remote Write Exporter - Metrics Export to Prometheus

This blueprint demonstrates how to use the OpenTelemetry Prometheus Remote Write exporter to send metrics to a Prometheus server using the remote write protocol, enabling integration with external Prometheus instances and cloud monitoring services.

## 🎯 Use Case

- **External Prometheus Integration**: Send metrics to remote Prometheus instances
- **Cloud Monitoring**: Export to managed Prometheus services (GCP, AWS, Azure)
- **Multi-Cluster Aggregation**: Centralize metrics from multiple clusters
- **Long-term Storage**: Use Prometheus with long-term storage solutions
- **Observability Platforms**: Integrate with external observability systems

## 📋 What You'll Deploy

- **Prometheus Server**: Target for remote write operations
- **OpenTelemetry Collector**: Configured with Prometheus Remote Write exporter
- **TLS Security**: Secure communication with certificates
- **Sample Application**: Metrics generator for testing

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- `openssl` for certificate generation

### Step 1: Generate TLS Certificates

Create certificates for secure communication:

```bash
# Create certificate generation script
cat > generate_certs.sh << 'EOF'
#!/bin/bash
set -e

echo "Generating TLS certificates for Prometheus Remote Write..."

# Generate CA private key and certificate
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout ca.key -out ca.crt \
  -subj '/CN=MyDemoCA'

# Generate server private key and certificate
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout cert.key -out cert.crt \
  -CA ca.crt -CAkey ca.key \
  -subj "/CN=prometheus" \
  -addext "subjectAltName=DNS:prometheus,DNS:prometheus.prometheus-demo.svc,DNS:prometheus.prometheus-demo.svc.cluster.local"

echo "Certificates generated successfully!"
echo "Files created: ca.crt, ca.key, cert.crt, cert.key"
EOF

chmod +x generate_certs.sh
./generate_certs.sh
```

### Step 2: Create Namespace and Secrets

```bash
# Create dedicated namespace
kubectl create namespace prometheus-demo

# Create secrets for certificates
kubectl create secret generic prometheus-ca \
  --from-file=ca.crt \
  -n prometheus-demo

kubectl create secret tls prometheus-certs \
  --cert=cert.crt \
  --key=cert.key \
  -n prometheus-demo

# Set current namespace
kubectl config set-context --current --namespace=prometheus-demo
```

### Step 3: Deploy Prometheus Server

Create a Prometheus server that accepts remote write:

```yaml
# prometheus-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: prometheus-demo
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    remote_write:
      - url: "https://prometheus.prometheus-demo.svc:9090/api/v1/write"
        tls_config:
          ca_file: /etc/ssl/certs/ca.crt
          cert_file: /etc/ssl/certs/tls.crt
          key_file: /etc/ssl/certs/tls.key
          insecure_skip_verify: false
    
    scrape_configs:
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']
    
    - job_name: 'otel-collector'
      static_configs:
      - targets: ['otel-collector:8888']
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: prometheus-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.45.0
        args:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus/'
        - '--web.console.libraries=/usr/share/prometheus/console_libraries'
        - '--web.console.templates=/usr/share/prometheus/consoles'
        - '--web.enable-lifecycle'
        - '--web.enable-remote-write-receiver'
        - '--web.listen-address=0.0.0.0:9090'
        ports:
        - containerPort: 9090
          name: web
        volumeMounts:
        - name: prometheus-config
          mountPath: /etc/prometheus
        - name: prometheus-certs
          mountPath: /etc/ssl/certs
          readOnly: true
        - name: prometheus-ca
          mountPath: /etc/ssl/ca
          readOnly: true
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: 9090
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /-/ready
            port: 9090
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
      - name: prometheus-certs
        secret:
          secretName: prometheus-certs
      - name: prometheus-ca
        secret:
          secretName: prometheus-ca
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: prometheus-demo
spec:
  selector:
    app: prometheus
  ports:
  - name: web
    port: 9090
    targetPort: 9090
  type: ClusterIP
```

Apply Prometheus deployment:

```bash
kubectl apply -f prometheus-deployment.yaml

# Wait for Prometheus to be ready
kubectl wait --for=condition=available deployment/prometheus --timeout=300s
```

### Step 4: Deploy OpenTelemetry Collector

Create collector with Prometheus Remote Write exporter:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: prometheus-demo
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      # Self-monitoring
      prometheus/self:
        config:
          scrape_configs:
          - job_name: 'otel-collector'
            scrape_interval: 30s
            static_configs:
            - targets: ['localhost:8888']
    
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
          value: "prometheus-demo-cluster"
          action: upsert
        - key: exporter.type
          value: "prometheus-remote-write"
          action: upsert
      
      # Transform metrics for better organization
      transform:
        metric_statements:
        - context: metric
          statements:
          # Add prefix to distinguish external metrics
          - set(name, "otel_" + name) where name matches "^(http_requests|cpu_usage|memory_usage).*"
          
        - context: datapoint
          statements:
          # Add additional labels
          - set(attributes["source"], "opentelemetry")
          - set(attributes["environment"], "demo")
    
    exporters:
      prometheusremotewrite:
        endpoint: "https://prometheus.prometheus-demo.svc:9090/api/v1/write"
        
        # TLS configuration
        tls:
          ca_file: "/etc/ssl/ca/ca.crt"
          cert_file: "/etc/ssl/certs/tls.crt"
          key_file: "/etc/ssl/certs/tls.key"
          insecure_skip_verify: false
        
        # Authentication (if required)
        # headers:
        #   Authorization: "Bearer YOUR_TOKEN"
        #   X-Scope-OrgID: "tenant-1"
        
        # Remote write configuration
        remote_write_queue:
          enabled: true
          queue_size: 2000
          num_consumers: 10
        
        # Resource to metric labels conversion
        resource_to_telemetry_conversion:
          enabled: true
        
        # Metric relabeling
        metric_relabels:
        - source_labels: [__name__]
          target_label: original_name
        - source_labels: [cluster.name]
          target_label: cluster
        
        # Target info configuration
        target_info:
          enabled: true
        
        # Compression
        compression: snappy
        
        # Retry configuration
        retry_on_failure:
          enabled: true
          initial_interval: 5s
          max_interval: 30s
          max_elapsed_time: 300s
      
      debug:
        verbosity: basic
    
    service:
      telemetry:
        metrics:
          address: 0.0.0.0:8888
      
      pipelines:
        metrics:
          receivers: [otlp, prometheus/self]
          processors: [memory_limiter, resource, transform, batch]
          exporters: [prometheusremotewrite, debug]
  
  # Mount certificates
  volumeMounts:
  - name: prometheus-certs
    mountPath: /etc/ssl/certs
    readOnly: true
  - name: prometheus-ca
    mountPath: /etc/ssl/ca
    readOnly: true
  
  volumes:
  - name: prometheus-certs
    secret:
      secretName: prometheus-certs
  - name: prometheus-ca
    secret:
      secretName: prometheus-ca
```

Apply collector configuration:

```bash
kubectl apply -f otel-collector.yaml

# Wait for collector to be ready
kubectl wait --for=condition=available deployment/otel-collector-collector --timeout=300s
```

### Step 5: Deploy Metrics Generator

Create an application that generates sample metrics:

```yaml
# metrics-generator.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-generator
  namespace: prometheus-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: metrics-generator
  template:
    metadata:
      labels:
        app: metrics-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          set -e
          
          OTEL_ENDPOINT="http://otel-collector-collector.prometheus-demo.svc:4318"
          HOSTNAME=$(hostname)
          
          # Function to send metrics
          send_metric() {
            local metric_name=$1
            local metric_value=$2
            local metric_type=${3:-gauge}
            local labels=$4
            
            local payload
            if [ "$metric_type" = "counter" ]; then
              payload='{
                "resourceMetrics": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "metrics-generator"}
                    }, {
                      "key": "host.name", 
                      "value": {"stringValue": "'$HOSTNAME'"}
                    }]
                  },
                  "scopeMetrics": [{
                    "metrics": [{
                      "name": "'$metric_name'",
                      "unit": "1",
                      "sum": {
                        "dataPoints": [{
                          "timeUnixNano": "'$(date +%s%N)'",
                          "asInt": "'$metric_value'",
                          "attributes": '$labels'
                        }],
                        "aggregationTemporality": 2,
                        "isMonotonic": true
                      }
                    }]
                  }]
                }]
              }'
            else
              payload='{
                "resourceMetrics": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "metrics-generator"}
                    }, {
                      "key": "host.name",
                      "value": {"stringValue": "'$HOSTNAME'"}
                    }]
                  },
                  "scopeMetrics": [{
                    "metrics": [{
                      "name": "'$metric_name'",
                      "unit": "1",
                      "gauge": {
                        "dataPoints": [{
                          "timeUnixNano": "'$(date +%s%N)'",
                          "asDouble": '$metric_value',
                          "attributes": '$labels'
                        }]
                      }
                    }]
                  }]
                }]
              }'
            fi
            
            curl -X POST ${OTEL_ENDPOINT}/v1/metrics \
              -H "Content-Type: application/json" \
              -d "$payload" > /dev/null 2>&1 || echo "Failed to send metric"
          }
          
          counter=0
          
          while true; do
            counter=$((counter + 1))
            
            # HTTP requests counter
            send_metric "http_requests_total" "$counter" "counter" '[{
              "key": "method",
              "value": {"stringValue": "GET"}
            }, {
              "key": "status_code",
              "value": {"stringValue": "200"}
            }]'
            
            # CPU usage gauge
            cpu_usage=$(echo "scale=2; $RANDOM / 327.67" | bc)
            send_metric "cpu_usage_percent" "$cpu_usage" "gauge" '[{
              "key": "core",
              "value": {"stringValue": "cpu0"}
            }]'
            
            # Memory usage gauge
            memory_usage=$(echo "scale=2; 50 + $RANDOM / 655.35" | bc)
            send_metric "memory_usage_percent" "$memory_usage" "gauge" '[{
              "key": "type",
              "value": {"stringValue": "physical"}
            }]'
            
            # Business metrics
            order_count=$((RANDOM % 20 + 1))
            send_metric "orders_processed_total" "$order_count" "counter" '[{
              "key": "region", 
              "value": {"stringValue": "us-west"}
            }]'
            
            echo "$(date): Sent metrics batch $counter from $HOSTNAME"
            sleep 15
          done
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
```

Apply metrics generator:

```bash
kubectl apply -f metrics-generator.yaml

# Wait for generator to be ready
kubectl wait --for=condition=available deployment/metrics-generator --timeout=300s
```

### Step 6: Verify Remote Write Functionality

Check that metrics are being sent and received:

```bash
# Check collector logs
kubectl logs deployment/otel-collector-collector -f --tail=50

# Check Prometheus logs
kubectl logs deployment/prometheus -f --tail=20

# Check metrics generator logs
kubectl logs deployment/metrics-generator -f --tail=10
```

### Step 7: Query Metrics in Prometheus

Access Prometheus to verify metrics:

```bash
# Port forward to Prometheus
kubectl port-forward svc/prometheus 9090:9090 &

# Query received metrics
curl -G "http://localhost:9090/api/v1/query" \
  --data-urlencode 'query=otel_http_requests_total'

curl -G "http://localhost:9090/api/v1/query" \
  --data-urlencode 'query=otel_cpu_usage_percent'

# Check in Prometheus UI
echo "Open http://localhost:9090 in your browser"
echo "Try queries like: otel_http_requests_total, otel_cpu_usage_percent"
```

### Step 8: Run Verification Script

```bash
# Create verification script
cat > check_metrics.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking Prometheus Remote Write functionality..."

# Wait for metrics to be sent
sleep 60

# Check if Prometheus is receiving metrics
echo "Checking Prometheus for OTEL metrics..."

# Port forward to Prometheus (background)
kubectl port-forward svc/prometheus 9090:9090 &
FORWARD_PID=$!
sleep 5

# Query for OTEL metrics
METRICS=(
    "otel_http_requests_total"
    "otel_cpu_usage_percent" 
    "otel_memory_usage_percent"
    "otel_orders_processed_total"
)

for metric in "${METRICS[@]}"; do
    result=$(curl -s -G "http://localhost:9090/api/v1/query" \
      --data-urlencode "query=$metric" | jq -r '.data.result | length')
    
    if [ "$result" != "null" ] && [ "$result" -gt 0 ]; then
        echo "✓ $metric found in Prometheus"
    else
        echo "✗ $metric not found in Prometheus"
    fi
done

# Check collector self-metrics
self_metrics=$(curl -s -G "http://localhost:9090/api/v1/query" \
  --data-urlencode "query=otelcol_processor_batch_batch_send_size_sum" | jq -r '.data.result | length')

if [ "$self_metrics" != "null" ] && [ "$self_metrics" -gt 0 ]; then
    echo "✓ Collector self-metrics found"
else
    echo "✗ Collector self-metrics not found"
fi

# Clean up
kill $FORWARD_PID 2>/dev/null || true

echo "Remote write verification completed!"
EOF

chmod +x check_metrics.sh
./check_metrics.sh
```

## 🔧 Advanced Configuration

### Authentication and Authorization

For Prometheus instances requiring authentication:

```yaml
exporters:
  prometheusremotewrite:
    endpoint: "https://prometheus.example.com/api/v1/write"
    headers:
      Authorization: "Bearer YOUR_API_TOKEN"
      X-Scope-OrgID: "tenant-1"
    
    # Basic authentication
    auth:
      authenticator: basicauth/prometheus
```

### Multi-Tenant Configuration

Send to multiple Prometheus instances:

```yaml
exporters:
  prometheusremotewrite/tenant1:
    endpoint: "https://tenant1.prometheus.com/api/v1/write"
    headers:
      X-Scope-OrgID: "tenant-1"
  
  prometheusremotewrite/tenant2:
    endpoint: "https://tenant2.prometheus.com/api/v1/write" 
    headers:
      X-Scope-OrgID: "tenant-2"

service:
  pipelines:
    metrics/tenant1:
      receivers: [otlp]
      processors: [filter/tenant1, batch]
      exporters: [prometheusremotewrite/tenant1]
    
    metrics/tenant2:
      receivers: [otlp]
      processors: [filter/tenant2, batch]
      exporters: [prometheusremotewrite/tenant2]
```

### Performance Optimization

For high-throughput scenarios:

```yaml
exporters:
  prometheusremotewrite:
    remote_write_queue:
      enabled: true
      queue_size: 10000
      num_consumers: 20
    
    # Compression
    compression: snappy
    
    # Batching
    max_batch_size_bytes: 10MB
    
    # Timeout settings
    timeout: 30s
    
    # Retry configuration
    retry_on_failure:
      enabled: true
      initial_interval: 1s
      max_interval: 10s
      max_elapsed_time: 60s
```

## 🔍 Monitoring and Observability

### Key Metrics to Monitor

```bash
# Remote write success rate
otelcol_exporter_sent_metric_points_total / otelcol_exporter_send_failed_metric_points_total

# Queue depth
otelcol_exporter_queue_size

# Send latency
otelcol_exporter_send_latency_seconds
```

### Health Checks

```bash
# Check collector health
kubectl port-forward svc/otel-collector-collector 13133:13133 &
curl http://localhost:13133/

# Check Prometheus write endpoint
kubectl port-forward svc/prometheus 9090:9090 &
curl -X POST http://localhost:9090/api/v1/write \
  -H "Content-Type: application/x-protobuf" \
  -H "Content-Encoding: snappy" \
  --data-binary @/dev/null
```

## 🚨 Troubleshooting

### Connection Issues

```bash
# Test TLS connectivity
kubectl exec deployment/otel-collector-collector -- \
  openssl s_client -connect prometheus.prometheus-demo.svc:9090 -servername prometheus

# Check certificate validity
kubectl exec deployment/otel-collector-collector -- \
  openssl x509 -in /etc/ssl/certs/tls.crt -text -noout
```

### Authentication Failures

```bash
# Check collector logs for auth errors
kubectl logs deployment/otel-collector-collector | grep -i "auth\|unauthorized\|forbidden"

# Verify headers and credentials
kubectl describe secret prometheus-certs
```

### Performance Issues

```bash
# Check queue metrics
kubectl port-forward svc/otel-collector-collector 8888:8888 &
curl http://localhost:8888/metrics | grep "queue"

# Monitor memory usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector
```

## 🔐 Security Considerations

1. **TLS Encryption**: Configure TLS for secure communication
2. **Certificate Management**: Implement certificate rotation
3. **Authentication**: Use strong authentication mechanisms
4. **Network Policies**: Restrict network access
5. **Secret Management**: Secure credential storage

## 📊 Cloud Service Integration

### AWS Managed Prometheus

```yaml
exporters:
  prometheusremotewrite:
    endpoint: "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-12345/api/v1/remote_write"
    auth:
      authenticator: sigv4auth
```

### Google Cloud Monitoring

```yaml
exporters:
  googlemanagedprometheus:
    project: "your-gcp-project"
    user_agent: "opentelemetry-collector"
```

### Azure Monitor

```yaml
exporters:
  prometheusremotewrite:
    endpoint: "https://your-workspace.prometheus.monitor.azure.com/api/v1/write"
    headers:
      Authorization: "Bearer YOUR_AZURE_TOKEN"
```

## 📚 Related Patterns

- [hostmetricsreceiver](../hostmetricsreceiver/) - For system metrics collection
- [k8sclusterreceiver](../k8sclusterreceiver/) - For Kubernetes metrics
- [transformprocessor](../transformprocessor/) - For metric transformation

## 🧹 Cleanup

```bash
# Remove metrics generator
kubectl delete deployment metrics-generator

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector otel-collector

# Remove Prometheus
kubectl delete deployment prometheus
kubectl delete service prometheus
kubectl delete configmap prometheus-config

# Remove secrets
kubectl delete secret prometheus-certs prometheus-ca

# Remove namespace
kubectl delete namespace prometheus-demo

# Clean up certificates
rm -f ca.crt ca.key cert.crt cert.key generate_certs.sh
```