# Routing Connector - Multi-Tenant Data Routing

This blueprint demonstrates how to use the OpenTelemetry Routing Connector to intelligently route telemetry data to different backends based on attributes, enabling multi-tenant architectures and sophisticated data distribution patterns.

## 🎯 Use Case

- **Multi-Tenant Systems**: Route telemetry data by tenant to isolated backends
- **Environment Separation**: Send data to different backends based on environment (dev/staging/prod)
- **Service-Based Routing**: Route telemetry by service or application to specialized systems
- **Geographic Distribution**: Route data based on geographical attributes
- **Cost Optimization**: Route high-volume data to cost-effective storage solutions

## 📋 What You'll Deploy

- **Routing Collector**: OpenTelemetry collector with routing connector logic
- **Multiple Tempo Backends**: Separate Tempo instances for different tenants/routes
- **Tenant-Specific Trace Generators**: Applications generating traces with routing attributes
- **OTTL-Based Routing Rules**: Conditional routing using OpenTelemetry Transformation Language

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- Tempo Operator installed
- `kubectl` or `oc` CLI tool configured
- Understanding of OTTL (OpenTelemetry Transformation Language)

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace routingconnector-demo

# Set as current namespace
kubectl config set-context --current --namespace=routingconnector-demo
```

### Step 2: Deploy Multiple Tempo Backends

Create separate Tempo instances for different tenants:

```yaml
# install-tempo.yaml
---
apiVersion: tempo.grafana.com/v1alpha1
kind: TempoMonolithic
metadata:
  name: red
  namespace: routingconnector-demo
  labels:
    tenant: red
spec:
  jaegerui:
    enabled: true
    route:
      enabled: true
  
  # Optional: Resource limits for tenant isolation
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "200m"

---
apiVersion: tempo.grafana.com/v1alpha1
kind: TempoMonolithic
metadata:
  name: blue
  namespace: routingconnector-demo
  labels:
    tenant: blue
spec:
  jaegerui:
    enabled: true
    route:
      enabled: true
  
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "200m"

---
apiVersion: tempo.grafana.com/v1alpha1
kind: TempoMonolithic
metadata:
  name: green
  namespace: routingconnector-demo
  labels:
    tenant: green
spec:
  jaegerui:
    enabled: true
    route:
      enabled: true
  
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "200m"
```

Apply Tempo installations:

```bash
kubectl apply -f install-tempo.yaml

# Wait for all Tempo instances to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tempo --timeout=600s
```

### Step 3: Deploy Routing Collector

Create the collector with routing connector logic:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: routing
  namespace: routingconnector-demo
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
      
      # Memory limiter
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
      
      # Add routing metadata
      attributes:
        actions:
        - key: routing.processed
          value: "true"
          action: insert
        - key: routing.timestamp
          value: "{{.Now}}"
          action: insert
    
    exporters:
      # OTLP exporters for each tenant backend
      otlp/red:
        endpoint: tempo-red:4317
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
      
      otlp/blue:
        endpoint: tempo-blue:4317
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
      
      otlp/green:
        endpoint: tempo-green:4317
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
      
      # Debug exporter for monitoring
      debug:
        verbosity: basic
    
    connectors:
      # Routing connector with OTTL-based rules
      routing:
        # Error handling mode
        error_mode: ignore  # Options: ignore, propagate
        
        # Default pipelines for unmatched data
        default_pipelines: [traces/green]
        
        # Routing table with OTTL statements
        table:
        # Route red tenant traces
        - statement: route() where attributes["X-Tenant"] == "red"
          pipelines: [traces/red]
          
        # Route blue tenant traces
        - statement: route() where attributes["X-Tenant"] == "blue"
          pipelines: [traces/blue]
          
        # Advanced routing examples (uncomment to test)
        # - statement: route() where attributes["environment"] == "production"
        #   pipelines: [traces/red]
        #   
        # - statement: route() where attributes["service.name"] == "critical-service"
        #   pipelines: [traces/red, traces/blue]  # Multi-destination routing
        #   
        # - statement: route() where resource.attributes["k8s.namespace.name"] == "monitoring"
        #   pipelines: [traces/green]
    
    service:
      pipelines:
        # Input pipeline - receives all telemetry
        traces/in:
          receivers: [otlp]
          processors: [memory_limiter, attributes, batch]
          exporters: [routing, debug]
        
        # Tenant-specific output pipelines
        traces/red:
          receivers: [routing]
          processors: []
          exporters: [otlp/red]
        
        traces/blue:
          receivers: [routing]
          processors: []
          exporters: [otlp/blue]
        
        traces/green:
          receivers: [routing]
          processors: []
          exporters: [otlp/green]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

Apply the routing collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for the collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=routing --timeout=300s
```

### Step 4: Generate Test Traces with Tenant Attributes

Create traces for different tenants to test routing:

```yaml
# generate-traces.yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces-red
  namespace: routingconnector-demo
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
        - --otlp-endpoint=routing-collector:4317
        - --otlp-insecure=true
        - --traces=10
        - --duration=30s
        - --rate=2
        - --service=red-tenant-service
        - --span-name=red-tenant-operation
        - --otlp-attributes=X-Tenant="red"
        - --otlp-attributes=environment="production"
        - --otlp-attributes=region="us-east-1"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never
  backoffLimit: 4

---
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces-blue
  namespace: routingconnector-demo
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
        - --otlp-endpoint=routing-collector:4317
        - --otlp-insecure=true
        - --traces=10
        - --duration=30s
        - --rate=2
        - --service=blue-tenant-service
        - --span-name=blue-tenant-operation
        - --otlp-attributes=X-Tenant="blue"
        - --otlp-attributes=environment="staging"
        - --otlp-attributes=region="us-west-2"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      restartPolicy: Never
  backoffLimit: 4

---
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces-green
  namespace: routingconnector-demo
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
        - --otlp-endpoint=routing-collector:4317
        - --otlp-insecure=true
        - --traces=10
        - --duration=30s
        - --rate=2
        - --service=default-service
        - --span-name=default-operation
        - --otlp-attributes=environment="development"
        - --otlp-attributes=region="eu-west-1"
        # Note: No X-Tenant attribute - should route to default (green)
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

Apply the trace generators:

```bash
kubectl apply -f generate-traces.yaml

# Monitor the jobs
kubectl get jobs -w
```

### Step 5: Verify Routing Functionality

Check that traces are routed to the correct backends:

```bash
# Check routing collector logs
kubectl logs -l app.kubernetes.io/name=routing --tail=100

# Check individual Tempo instances for traces
kubectl get pods -l app.kubernetes.io/name=tempo
```

### Step 6: Run Verification Jobs

Create verification jobs to check traces in each backend:

```yaml
# verify-traces.yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: verify-traces-red
  namespace: routingconnector-demo
spec:
  template:
    spec:
      containers:
      - name: verify-traces-red
        image: curlimages/curl:latest
        command:
        - /bin/sh
        - -c
        args:
        - |
          echo "Verifying red tenant traces..."
          
          # Wait for Jaeger UI to be ready
          until curl -s http://tempo-red-jaegerui:16686/api/services; do
            echo "Waiting for Red Jaeger UI..."
            sleep 5
          done
          
          # Query for red tenant traces
          curl -v -G http://tempo-red-jaegerui:16686/api/traces \
            --data-urlencode "service=red-tenant-service" \
            --data-urlencode "limit=20" | tee /tmp/jaeger.out
          
          # Check if we have traces (using grep since jq might not be available)
          if grep -q "red-tenant-service" /tmp/jaeger.out; then
            echo "✅ Red tenant traces found in red backend"
          else
            echo "❌ Red tenant traces not found in red backend"
            exit 1
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

---
apiVersion: batch/v1
kind: Job
metadata:
  name: verify-traces-blue
  namespace: routingconnector-demo
spec:
  template:
    spec:
      containers:
      - name: verify-traces-blue
        image: curlimages/curl:latest
        command:
        - /bin/sh
        - -c
        args:
        - |
          echo "Verifying blue tenant traces..."
          
          until curl -s http://tempo-blue-jaegerui:16686/api/services; do
            echo "Waiting for Blue Jaeger UI..."
            sleep 5
          done
          
          curl -v -G http://tempo-blue-jaegerui:16686/api/traces \
            --data-urlencode "service=blue-tenant-service" \
            --data-urlencode "limit=20" | tee /tmp/jaeger.out
          
          if grep -q "blue-tenant-service" /tmp/jaeger.out; then
            echo "✅ Blue tenant traces found in blue backend"
          else
            echo "❌ Blue tenant traces not found in blue backend"
            exit 1
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

---
apiVersion: batch/v1
kind: Job
metadata:
  name: verify-traces-green
  namespace: routingconnector-demo
spec:
  template:
    spec:
      containers:
      - name: verify-traces-green
        image: curlimages/curl:latest
        command:
        - /bin/sh
        - -c
        args:
        - |
          echo "Verifying default (green) tenant traces..."
          
          until curl -s http://tempo-green-jaegerui:16686/api/services; do
            echo "Waiting for Green Jaeger UI..."
            sleep 5
          done
          
          curl -v -G http://tempo-green-jaegerui:16686/api/traces \
            --data-urlencode "service=default-service" \
            --data-urlencode "limit=20" | tee /tmp/jaeger.out
          
          if grep -q "default-service" /tmp/jaeger.out; then
            echo "✅ Default traces found in green backend"
          else
            echo "❌ Default traces not found in green backend"
            exit 1
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

# Wait for all verification jobs to complete
kubectl wait --for=condition=complete job/verify-traces-red job/verify-traces-blue job/verify-traces-green --timeout=300s

# Check verification results
kubectl logs job/verify-traces-red
kubectl logs job/verify-traces-blue
kubectl logs job/verify-traces-green
```

### Step 7: Access Jaeger UIs (Optional)

Access the different Jaeger UIs to visualize tenant-specific traces:

```bash
# Red tenant UI
kubectl port-forward svc/tempo-red-jaegerui 16686:16686 &

# Blue tenant UI (different port)
kubectl port-forward svc/tempo-blue-jaegerui 16687:16686 &

# Green tenant UI (different port)
kubectl port-forward svc/tempo-green-jaegerui 16688:16686 &

# Open browsers to:
# Red: http://localhost:16686
# Blue: http://localhost:16687
# Green: http://localhost:16688
```

## 🔧 Advanced Configuration

### Complex Routing Rules

Use advanced OTTL expressions for sophisticated routing:

```yaml
connectors:
  routing:
    table:
    # Route by multiple conditions
    - statement: route() where attributes["X-Tenant"] == "red" and attributes["environment"] == "production"
      pipelines: [traces/red-prod]
      
    # Route by resource attributes
    - statement: route() where resource.attributes["k8s.namespace.name"] == "critical"
      pipelines: [traces/red, traces/blue]  # Multi-destination
      
    # Route by span attributes
    - statement: route() where attributes["http.status_code"] >= 500
      pipelines: [traces/errors]
      
    # Route by service name patterns
    - statement: route() where IsMatch(attributes["service.name"], ".*-critical-.*")
      pipelines: [traces/critical]
      
    # Route by geographic region
    - statement: route() where attributes["cloud.region"] in ["us-east-1", "us-west-2"]
      pipelines: [traces/us]
```

### Conditional Preprocessing

Add different processing based on routing destination:

```yaml
processors:
  # Different attribute processors for different tenants
  attributes/red:
    actions:
    - key: tenant.tier
      value: "premium"
      action: insert
      
  attributes/blue:
    actions:
    - key: tenant.tier
      value: "standard"
      action: insert

service:
  pipelines:
    traces/red:
      receivers: [routing]
      processors: [attributes/red, batch]
      exporters: [otlp/red]
```

### Sampling-Based Routing

Route different sample rates to different backends:

```yaml
processors:
  probabilistic_sampler/high:
    sampling_percentage: 100  # 100% sampling for critical
    
  probabilistic_sampler/low:
    sampling_percentage: 1    # 1% sampling for bulk

connectors:
  routing:
    table:
    - statement: route() where attributes["service.tier"] == "critical"
      pipelines: [traces/high-sampling]
    - statement: route() where attributes["service.tier"] == "bulk"
      pipelines: [traces/low-sampling]
```

### Fan-Out Routing

Send data to multiple destinations:

```yaml
connectors:
  routing:
    table:
    # Send critical data to multiple backends for redundancy
    - statement: route() where attributes["criticality"] == "high"
      pipelines: [traces/red, traces/blue, traces/archive]
      
    # Send audit data to compliance backend
    - statement: route() where attributes["audit.required"] == "true"
      pipelines: [traces/compliance, traces/default]
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check routing collector status
kubectl get opentelemetrycollector routing

# Check all Tempo backends
kubectl get tempomonolithic

# Check routing connector metrics
kubectl port-forward svc/routing-collector 8888:8888 &
curl http://localhost:8888/metrics | grep routing
```

### Common Issues

**Issue: Data not routing correctly**
```bash
# Check routing connector configuration
kubectl get opentelemetrycollector routing -o yaml | grep -A 20 routing:

# Check debug logs for routing decisions
kubectl logs -l app.kubernetes.io/name=routing | grep -i "routing\|route"

# Verify attributes in incoming data
kubectl logs -l app.kubernetes.io/name=routing | grep "X-Tenant"
```

**Issue: Default pipeline not working**
```bash
# Check default_pipelines configuration
kubectl get opentelemetrycollector routing -o yaml | grep -A 5 default_pipelines

# Verify green backend is receiving data
kubectl logs -l app.kubernetes.io/name=tempo,tempo.grafana.com/name=green
```

**Issue: OTTL statement errors**
```bash
# Check for OTTL parsing errors
kubectl logs -l app.kubernetes.io/name=routing | grep -i "ottl\|statement\|error"

# Validate OTTL syntax
kubectl get opentelemetrycollector routing -o yaml | grep -A 10 "statement:"
```

### Performance Monitoring

```bash
# Monitor routing latency
kubectl logs -l app.kubernetes.io/name=routing | grep -i "latency\|duration"

# Check pipeline throughput
kubectl port-forward svc/routing-collector 8888:8888 &
curl http://localhost:8888/metrics | grep -E "(received|sent)"
```

## 📊 Routing Patterns

### Geographic Routing

Route data based on geographic location:

```yaml
table:
- statement: route() where attributes["cloud.region"] in ["us-east-1", "us-east-2"]
  pipelines: [traces/us-east]
- statement: route() where attributes["cloud.region"] in ["eu-west-1", "eu-central-1"]
  pipelines: [traces/europe]
```

### Environment-Based Routing

Separate data by deployment environment:

```yaml
table:
- statement: route() where attributes["deployment.environment"] == "production"
  pipelines: [traces/prod]
- statement: route() where attributes["deployment.environment"] in ["staging", "test"]
  pipelines: [traces/non-prod]
```

### Service Tier Routing

Route by service criticality:

```yaml
table:
- statement: route() where attributes["service.tier"] == "tier1"
  pipelines: [traces/critical, traces/archive]
- statement: route() where attributes["service.tier"] == "tier2"
  pipelines: [traces/standard]
```

### Cost-Optimized Routing

Route high-volume data to cost-effective storage:

```yaml
table:
- statement: route() where attributes["data.volume"] == "high"
  pipelines: [traces/cold-storage]
- statement: route() where attributes["data.volume"] == "low"
  pipelines: [traces/hot-storage]
```

## 🔐 Security Considerations

1. **Tenant Isolation**: Ensure proper isolation between tenant backends
2. **Attribute Validation**: Validate routing attributes to prevent injection
3. **Access Control**: Implement RBAC for different tenant backends
4. **Data Encryption**: Use TLS for all backend connections

## 📚 Related Patterns

- [forwardconnector](../forwardconnector/) - For pipeline consolidation
- [transformprocessor](../transformprocessor/) - For attribute manipulation
- [filterprocessor](../filterprocessor/) - For conditional data filtering

## 🧹 Cleanup

```bash
# Remove verification jobs
kubectl delete job verify-traces-red verify-traces-blue verify-traces-green

# Remove trace generation jobs
kubectl delete job generate-traces-red generate-traces-blue generate-traces-green

# Remove routing collector
kubectl delete opentelemetrycollector routing

# Remove Tempo backends
kubectl delete tempomonolithic red blue green

# Remove namespace
kubectl delete namespace routingconnector-demo
```

## 📖 Additional Resources

- [OpenTelemetry Routing Connector Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/routingconnector)
- [OTTL (OpenTelemetry Transformation Language)](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/pkg/ottl)
- [Multi-Tenancy in Observability](https://opentelemetry.io/docs/collector/deployment/multi-tenancy/)
- [Tempo Multi-Tenancy](https://grafana.com/docs/tempo/latest/multitenancy/) 