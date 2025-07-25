# Load Balancing Exporter - High Availability Telemetry Distribution

This blueprint demonstrates how to use the OpenTelemetry Load Balancing exporter to distribute telemetry data across multiple backend instances, ensuring high availability, fault tolerance, and optimal load distribution.

## 🎯 Use Case

- **High Availability**: Eliminate single points of failure in telemetry pipelines
- **Load Distribution**: Distribute telemetry load across multiple backend instances
- **Fault Tolerance**: Automatic failover when backend instances become unavailable
- **Scalability**: Scale telemetry processing by adding backend instances
- **Performance Optimization**: Optimize throughput and reduce latency

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with load balancing exporter
- **Multiple Backend Instances**: Simulated OTLP receivers as backends
- **Load Balancing Strategies**: Round-robin and consistent hashing examples
- **Health Monitoring**: Backend health checks and automatic failover

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured

### Step 1: Create Namespace

```bash
# Create dedicated namespace
kubectl create namespace loadbalancer-demo

# Set as current namespace
kubectl config set-context --current --namespace=loadbalancer-demo
```

### Step 2: Deploy Multiple Backend Instances

Create multiple OTLP receiver instances to simulate backend services:

```yaml
# backend-instances.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-1
  namespace: loadbalancer-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend-1
  template:
    metadata:
      labels:
        app: backend-1
    spec:
      containers:
      - name: otel-receiver
        image: otel/opentelemetry-collector-contrib:0.129.1
        args:
        - --config=/etc/config/config.yaml
        ports:
        - containerPort: 4317
          name: otlp-grpc
        - containerPort: 4318
          name: otlp-http
        - containerPort: 8888
          name: metrics
        volumeMounts:
        - name: config
          mountPath: /etc/config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: backend-config
---
apiVersion: v1
kind: Service
metadata:
  name: backend-1
  namespace: loadbalancer-demo
spec:
  selector:
    app: backend-1
  ports:
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
  - name: otlp-http
    port: 4318
    targetPort: 4318
  - name: metrics
    port: 8888
    targetPort: 8888
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-2
  namespace: loadbalancer-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend-2
  template:
    metadata:
      labels:
        app: backend-2
    spec:
      containers:
      - name: otel-receiver
        image: otel/opentelemetry-collector-contrib:0.129.1
        args:
        - --config=/etc/config/config.yaml
        ports:
        - containerPort: 4317
          name: otlp-grpc
        - containerPort: 4318
          name: otlp-http
        - containerPort: 8888
          name: metrics
        volumeMounts:
        - name: config
          mountPath: /etc/config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: backend-config
---
apiVersion: v1
kind: Service
metadata:
  name: backend-2
  namespace: loadbalancer-demo
spec:
  selector:
    app: backend-2
  ports:
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
  - name: otlp-http
    port: 4318
    targetPort: 4318
  - name: metrics
    port: 8888
    targetPort: 8888
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-3
  namespace: loadbalancer-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend-3
  template:
    metadata:
      labels:
        app: backend-3
    spec:
      containers:
      - name: otel-receiver
        image: otel/opentelemetry-collector-contrib:0.129.1
        args:
        - --config=/etc/config/config.yaml
        ports:
        - containerPort: 4317
          name: otlp-grpc
        - containerPort: 4318
          name: otlp-http
        - containerPort: 8888
          name: metrics
        volumeMounts:
        - name: config
          mountPath: /etc/config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: backend-config
---
apiVersion: v1
kind: Service
metadata:
  name: backend-3
  namespace: loadbalancer-demo
spec:
  selector:
    app: backend-3
  ports:
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
  - name: otlp-http
    port: 4318
    targetPort: 4318
  - name: metrics
    port: 8888
    targetPort: 8888
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: loadbalancer-demo
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      batch:
        timeout: 5s
        send_batch_size: 1024
    
    exporters:
      debug:
        verbosity: detailed
    
    service:
      telemetry:
        metrics:
          address: 0.0.0.0:8888
      
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [debug]
        
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [debug]
        
        logs:
          receivers: [otlp]
          processors: [batch]
          exporters: [debug]
```

Apply backend instances:

```bash
kubectl apply -f backend-instances.yaml

# Wait for backends to be ready
kubectl wait --for=condition=available deployment/backend-1 --timeout=300s
kubectl wait --for=condition=available deployment/backend-2 --timeout=300s
kubectl wait --for=condition=available deployment/backend-3 --timeout=300s
```

### Step 3: Deploy Load Balancing Collector

Create the main collector with load balancing exporter:

```yaml
# loadbalancing-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: loadbalancer-collector
  namespace: loadbalancer-demo
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      # Generate self-metrics for monitoring
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
      
      # Add resource attributes for tracking
      resource:
        attributes:
        - key: cluster.name
          value: "loadbalancer-demo"
          action: upsert
        - key: collector.instance
          value: "load-balancer"
          action: upsert
    
    exporters:
      # Load balancing exporter with round-robin strategy
      loadbalancing:
        routing_key: "service"  # Route based on service.name attribute
        
        protocol:
          otlp:
            timeout: 10s
            retry_on_failure:
              enabled: true
              initial_interval: 1s
              max_interval: 5s
              max_elapsed_time: 30s
            
        resolver:
          static:
            hostnames:
            - "backend-1.loadbalancer-demo.svc.cluster.local:4317"
            - "backend-2.loadbalancer-demo.svc.cluster.local:4317"
            - "backend-3.loadbalancer-demo.svc.cluster.local:4317"
          
          # Alternative: DNS-based service discovery
          # dns:
          #   hostname: "backend-service.loadbalancer-demo.svc.cluster.local"
          #   port: 4317
          #   interval: 5s
          #   timeout: 1s
      
      # Alternative load balancing with consistent hashing
      loadbalancing/consistent:
        routing_key: "trace_id"  # Use trace ID for consistent routing
        
        protocol:
          otlp:
            timeout: 10s
            compression: gzip
            headers:
              x-lb-strategy: "consistent-hash"
        
        resolver:
          static:
            hostnames:
            - "backend-1.loadbalancer-demo.svc.cluster.local:4317"
            - "backend-2.loadbalancer-demo.svc.cluster.local:4317"
            - "backend-3.loadbalancer-demo.svc.cluster.local:4317"
      
      # Debug exporter for verification
      debug:
        verbosity: basic
    
    service:
      telemetry:
        metrics:
          address: 0.0.0.0:8888
      
      pipelines:
        # Main pipeline with round-robin load balancing
        traces:
          receivers: [otlp]
          processors: [memory_limiter, resource, batch]
          exporters: [loadbalancing, debug]
        
        metrics:
          receivers: [otlp, prometheus/self]
          processors: [memory_limiter, resource, batch]
          exporters: [loadbalancing, debug]
        
        logs:
          receivers: [otlp]
          processors: [memory_limiter, resource, batch]
          exporters: [loadbalancing, debug]
        
        # Alternative pipeline for traces requiring session affinity
        # traces/consistent:
        #   receivers: [otlp]
        #   processors: [memory_limiter, resource, batch]
        #   exporters: [loadbalancing/consistent, debug]
```

Apply load balancing collector:

```bash
kubectl apply -f loadbalancing-collector.yaml

# Wait for collector to be ready
kubectl wait --for=condition=available deployment/loadbalancer-collector-collector --timeout=300s
```

### Step 4: Deploy Telemetry Generators

Create applications that generate telemetry data with different service names:

```yaml
# telemetry-generators.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-a-generator
  namespace: loadbalancer-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: service-a-generator
  template:
    metadata:
      labels:
        app: service-a-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://loadbalancer-collector-collector.loadbalancer-demo.svc:4318"
          
          while true; do
            TRACE_ID=$(openssl rand -hex 16)
            SPAN_ID=$(openssl rand -hex 8)
            
            # Send traces
            curl -X POST ${OTEL_ENDPOINT}/v1/traces \
              -H "Content-Type: application/json" \
              -d '{
                "resourceSpans": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "service-a"}
                    }, {
                      "key": "service.version",
                      "value": {"stringValue": "1.0.0"}
                    }]
                  },
                  "scopeSpans": [{
                    "spans": [{
                      "traceId": "'$TRACE_ID'",
                      "spanId": "'$SPAN_ID'",
                      "name": "service-a-operation",
                      "startTimeUnixNano": "'$(date +%s%N)'",
                      "endTimeUnixNano": "'$(($(date +%s%N) + 100000000))'",
                      "attributes": [{
                        "key": "operation.type",
                        "value": {"stringValue": "database_query"}
                      }]
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Service A sent trace"
            sleep 5
          done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-b-generator
  namespace: loadbalancer-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: service-b-generator
  template:
    metadata:
      labels:
        app: service-b-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://loadbalancer-collector-collector.loadbalancer-demo.svc:4318"
          
          while true; do
            # Send metrics
            curl -X POST ${OTEL_ENDPOINT}/v1/metrics \
              -H "Content-Type: application/json" \
              -d '{
                "resourceMetrics": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "service-b"}
                    }, {
                      "key": "service.version",
                      "value": {"stringValue": "2.0.0"}
                    }]
                  },
                  "scopeMetrics": [{
                    "metrics": [{
                      "name": "requests_total",
                      "unit": "1",
                      "sum": {
                        "dataPoints": [{
                          "timeUnixNano": "'$(date +%s%N)'",
                          "asInt": "'$((RANDOM % 100 + 1))'",
                          "attributes": [{
                            "key": "status",
                            "value": {"stringValue": "success"}
                          }]
                        }],
                        "aggregationTemporality": 2,
                        "isMonotonic": true
                      }
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Service B sent metrics"
            sleep 7
          done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-c-generator
  namespace: loadbalancer-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: service-c-generator
  template:
    metadata:
      labels:
        app: service-c-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://loadbalancer-collector-collector.loadbalancer-demo.svc:4318"
          
          while true; do
            # Send logs
            curl -X POST ${OTEL_ENDPOINT}/v1/logs \
              -H "Content-Type: application/json" \
              -d '{
                "resourceLogs": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "service-c"}
                    }, {
                      "key": "service.version",
                      "value": {"stringValue": "3.0.0"}
                    }]
                  },
                  "scopeLogs": [{
                    "logRecords": [{
                      "timeUnixNano": "'$(date +%s%N)'",
                      "body": {
                        "stringValue": "Service C processing request #'$RANDOM'"
                      },
                      "attributes": [{
                        "key": "level",
                        "value": {"stringValue": "info"}
                      }]
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Service C sent logs"
            sleep 6
          done
```

Apply telemetry generators:

```bash
kubectl apply -f telemetry-generators.yaml

# Wait for generators to be ready
kubectl wait --for=condition=available deployment/service-a-generator --timeout=300s
kubectl wait --for=condition=available deployment/service-b-generator --timeout=300s
kubectl wait --for=condition=available deployment/service-c-generator --timeout=300s
```

### Step 5: Verify Load Balancing

Check that telemetry is being distributed across backends:

```bash
# Check load balancer collector logs
kubectl logs deployment/loadbalancer-collector-collector -f --tail=50

# Check backend-1 logs for received data
kubectl logs deployment/backend-1 -f --tail=20

# Check backend-2 logs for received data  
kubectl logs deployment/backend-2 -f --tail=20

# Check backend-3 logs for received data
kubectl logs deployment/backend-3 -f --tail=20
```

### Step 6: Run Load Balancing Verification Script

```bash
# Create verification script
cat > check_load_balancing.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking Load Balancing functionality..."

# Wait for data to flow
sleep 60

echo "Checking data distribution across backends..."

# Count telemetry data in each backend
BACKEND_1_COUNT=$(kubectl logs deployment/backend-1 --tail=1000 | grep -c "resourceSpans\|resourceMetrics\|resourceLogs" || true)
BACKEND_2_COUNT=$(kubectl logs deployment/backend-2 --tail=1000 | grep -c "resourceSpans\|resourceMetrics\|resourceLogs" || true)
BACKEND_3_COUNT=$(kubectl logs deployment/backend-3 --tail=1000 | grep -c "resourceSpans\|resourceMetrics\|resourceLogs" || true)

echo "Backend 1 received: $BACKEND_1_COUNT telemetry batches"
echo "Backend 2 received: $BACKEND_2_COUNT telemetry batches"
echo "Backend 3 received: $BACKEND_3_COUNT telemetry batches"

TOTAL_COUNT=$((BACKEND_1_COUNT + BACKEND_2_COUNT + BACKEND_3_COUNT))

if [ "$TOTAL_COUNT" -gt 0 ]; then
    echo "✓ Load balancing is working - total telemetry batches: $TOTAL_COUNT"
    
    # Check if distribution is reasonably balanced (no backend should have 0)
    if [ "$BACKEND_1_COUNT" -gt 0 ] && [ "$BACKEND_2_COUNT" -gt 0 ] && [ "$BACKEND_3_COUNT" -gt 0 ]; then
        echo "✓ Load is distributed across all backends"
    else
        echo "⚠ Load distribution may be uneven"
    fi
else
    echo "✗ No telemetry data found in backends"
    exit 1
fi

# Check load balancer collector logs for routing
LB_LOGS=$(kubectl logs deployment/loadbalancer-collector-collector --tail=500)

echo $LB_LOGS | grep -q "loadbalancing"
if [ $? -eq 0 ]; then
    echo "✓ Load balancing exporter is active"
else
    echo "✗ Load balancing exporter not found in logs"
fi

# Check for backend health monitoring
echo $LB_LOGS | grep -q "backend\|endpoint"
if [ $? -eq 0 ]; then
    echo "✓ Backend endpoint monitoring detected"
else
    echo "✗ Backend endpoint monitoring not found"
fi

echo "Load balancing verification completed!"
EOF

chmod +x check_load_balancing.sh
./check_load_balancing.sh
```

## 🔧 Advanced Configuration

### Consistent Hashing Strategy

For session affinity and trace continuity:

```yaml
exporters:
  loadbalancing/consistent:
    routing_key: "trace_id"  # Ensures trace spans go to same backend
    
    protocol:
      otlp:
        timeout: 10s
    
    resolver:
      static:
        hostnames:
        - "backend-1:4317"
        - "backend-2:4317" 
        - "backend-3:4317"
```

### DNS-Based Service Discovery

For dynamic backend discovery:

```yaml
exporters:
  loadbalancing/dns:
    routing_key: "service"
    
    resolver:
      dns:
        hostname: "backend-service.namespace.svc.cluster.local"
        port: 4317
        interval: 10s  # Refresh interval
        timeout: 2s
```

### Health Check Configuration

Monitor backend health:

```yaml
exporters:
  loadbalancing/health:
    routing_key: "service"
    
    protocol:
      otlp:
        timeout: 5s
        
    resolver:
      static:
        hostnames:
        - "backend-1:4317"
        - "backend-2:4317"
        - "backend-3:4317"
      
      # Health check settings
      health_check:
        enabled: true
        interval: 30s
        timeout: 5s
        healthy_threshold: 2
        unhealthy_threshold: 3
```

### Weighted Load Balancing

Distribute load based on backend capacity:

```yaml
exporters:
  loadbalancing/weighted:
    routing_key: "service"
    
    resolver:
      static:
        hostnames:
        - "backend-1:4317"  # Weight: 1 (default)
        - "backend-2:4317"  # Weight: 2 (handles 2x traffic)
        - "backend-3:4317"  # Weight: 1 (default)
        
        weights: [1, 2, 1]  # Corresponds to hostnames order
```

## 🔍 Monitoring and Observability

### Key Metrics to Monitor

```bash
# Load balancer metrics
otelcol_loadbalancer_backend_latency
otelcol_loadbalancer_backend_outcome
otelcol_loadbalancer_num_backends

# Backend health
otelcol_loadbalancer_backend_health

# Data distribution
otelcol_exporter_sent_spans_total
otelcol_exporter_sent_metric_points_total
```

### Health Checks

```bash
# Check backend connectivity
kubectl port-forward svc/backend-1 4317:4317 &
grpcurl -plaintext localhost:4317 list

# Monitor load balancer status
kubectl port-forward svc/loadbalancer-collector-collector 8888:8888 &
curl http://localhost:8888/metrics | grep loadbalancer
```

## 🚨 Troubleshooting

### Backend Connectivity Issues

```bash
# Test backend connectivity
kubectl exec deployment/loadbalancer-collector-collector -- \
  nc -zv backend-1.loadbalancer-demo.svc.cluster.local 4317

# Check DNS resolution
kubectl exec deployment/loadbalancer-collector-collector -- \
  nslookup backend-1.loadbalancer-demo.svc.cluster.local

# Verify service endpoints
kubectl get endpoints
```

### Uneven Load Distribution

```bash
# Check routing key configuration
kubectl logs deployment/loadbalancer-collector-collector | grep "routing_key"

# Monitor backend selection
kubectl logs deployment/loadbalancer-collector-collector | grep -i "backend\|endpoint"

# Verify service attributes in data
kubectl logs deployment/loadbalancer-collector-collector | grep "service.name"
```

### Performance Issues

```bash
# Check exporter queue sizes
kubectl port-forward svc/loadbalancer-collector-collector 8888:8888 &
curl http://localhost:8888/metrics | grep queue

# Monitor timeout and retry metrics
curl http://localhost:8888/metrics | grep -E "(timeout|retry|failed)"

# Check resource usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector
```

## 🔐 Security Considerations

1. **TLS Encryption**: Enable TLS for backend communication
2. **Authentication**: Use proper authentication between components
3. **Network Policies**: Restrict network access between components
4. **Resource Limits**: Set appropriate limits to prevent resource exhaustion

## 📊 Configuration Examples

### Routing Key Selection

- **service**: Route by service name for service-specific backends
- **trace_id**: Maintain trace continuity in the same backend
- **tenant_id**: Multi-tenant scenarios with tenant-specific backends

### Backend Pool Management

```yaml
# Advanced configuration example
exporters:
  loadbalancing/prod:
    routing_key: "service"
    
    protocol:
      otlp:
        timeout: 10s
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
          max_elapsed_time: 300s
        
        # Enable compression for efficiency
        compression: gzip
        
        # TLS configuration
        tls:
          ca_file: "/etc/ssl/ca.crt"
          cert_file: "/etc/ssl/client.crt"
          key_file: "/etc/ssl/client.key"
    
    resolver:
      dns:
        hostname: "backend-pool.production.svc.cluster.local"
        port: 4317
        interval: 30s
        timeout: 5s
```

## 📚 Related Patterns

- [prometheusremotewriteexporter](../prometheusremotewriteexporter/) - For metrics-specific load balancing
- [transformprocessor](../transformprocessor/) - For data transformation before load balancing
- [filterprocessor](../filterprocessor/) - For selective data routing

## 🧹 Cleanup

```bash
# Remove telemetry generators
kubectl delete deployment service-a-generator service-b-generator service-c-generator

# Remove load balancing collector
kubectl delete opentelemetrycollector loadbalancer-collector

# Remove backend instances
kubectl delete deployment backend-1 backend-2 backend-3
kubectl delete service backend-1 backend-2 backend-3
kubectl delete configmap backend-config

# Remove namespace
kubectl delete namespace loadbalancer-demo
``` 