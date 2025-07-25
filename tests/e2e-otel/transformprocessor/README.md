# Transform Processor - Advanced Data Transformation and Enrichment

This blueprint demonstrates how to use the OpenTelemetry Transform processor to modify, enrich, and standardize telemetry data (metrics, logs, and traces) as it flows through the collector pipeline.

## 🎯 Use Case

- **Data Standardization**: Normalize telemetry data formats and field names
- **Attribute Enrichment**: Add contextual information and business metadata
- **Privacy Protection**: Remove or mask sensitive information
- **Cost Optimization**: Filter and reduce high-cardinality data
- **Data Routing**: Conditional data transformation for different destinations

## 📋 What You'll Deploy

- **OpenTelemetry Collector**: Configured with comprehensive transform processors
- **Sample Applications**: Generate metrics, logs, and traces for transformation
- **Multiple Transform Examples**: Covering different transformation scenarios
- **Verification Tools**: Scripts to validate transformations

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured

### Step 1: Create Namespace

```bash
# Create dedicated namespace
kubectl create namespace transform-demo

# Set as current namespace
kubectl config set-context --current --namespace=transform-demo
```

### Step 2: Deploy OpenTelemetry Collector with Transform Processors

Create a comprehensive collector configuration demonstrating various transformation scenarios:

```yaml
# otel-collector.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: transform-collector
  namespace: transform-demo
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      # Memory limiter to prevent OOM
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 15
      
      # Batch processor for efficiency
      batch:
        timeout: 5s
        send_batch_size: 1024
      
      # Resource attribute transformation
      resource_transform:
        resource_statements:
        # Add cluster-level attributes
        - set(attributes["cluster.name"], "transform-demo-cluster")
        - set(attributes["environment"], "development")
        - set(attributes["region"], "us-west-2")
        
        # Normalize service names
        - set(attributes["service.name"], Concat([attributes["service.name"], "-svc"], "")) where attributes["service.name"] != nil
        
        # Add service version if missing
        - set(attributes["service.version"], "unknown") where attributes["service.version"] == nil
        
        # Convert deployment environment to lowercase
        - set(attributes["deployment.environment"], LowerCase(attributes["deployment.environment"])) where attributes["deployment.environment"] != nil
      
      # Metric-specific transformations
      transform/metrics:
        metric_statements:
        # Rename metrics for consistency
        - set(name, "http_request_duration") where name == "http_request_duration_seconds"
        - set(name, "http_requests_total") where name == "http_requests"
        
        # Add metric descriptions
        - set(description, "Total number of HTTP requests") where name == "http_requests_total"
        - set(description, "HTTP request duration in seconds") where name == "http_request_duration"
        
        # Convert units (milliseconds to seconds)
        - set(unit, "s") where name == "http_request_duration"
        
        datapoint_statements:
        # Add business context attributes
        - set(attributes["business_unit"], "ecommerce") where resource.attributes["service.name"] matches ".*shop.*"
        - set(attributes["criticality"], "high") where resource.attributes["service.name"] matches ".*(payment|auth|order).*"
        
        # Normalize HTTP status codes
        - set(attributes["status_class"], "success") where Int(attributes["status_code"]) >= 200 and Int(attributes["status_code"]) < 300
        - set(attributes["status_class"], "client_error") where Int(attributes["status_code"]) >= 400 and Int(attributes["status_code"]) < 500
        - set(attributes["status_class"], "server_error") where Int(attributes["status_code"]) >= 500
        
        # Add geographic region based on service location
        - set(attributes["geo.region"], "north_america") where attributes["datacenter"] matches "^(us|ca)-.*"
        - set(attributes["geo.region"], "europe") where attributes["datacenter"] matches "^eu-.*"
        
        # Sanitize sensitive data
        - delete_key(attributes, "user_id") where attributes["environment"] == "production"
        - replace_pattern(attributes["url"], "token=[^&]*", "token=***") where attributes["url"] != nil
        
        # Calculate derived metrics
        - set(attributes["request_rate_class"], "low") where Double(value) < 10.0
        - set(attributes["request_rate_class"], "medium") where Double(value) >= 10.0 and Double(value) < 100.0
        - set(attributes["request_rate_class"], "high") where Double(value) >= 100.0
      
      # Log-specific transformations  
      transform/logs:
        log_statements:
        # Extract structured data from log messages
        - merge_maps(cache, ExtractPatterns(body, "level=(?P<extracted_level>\\w+)"), "upsert") where IsMatch(body, "level=\\w+")
        - set(attributes["log.level"], cache["extracted_level"]) where cache["extracted_level"] != nil
        
        # Parse JSON logs
        - merge_maps(cache, ParseJSON(body), "upsert") where IsMatch(body, "^\\s*{.*}\\s*$")
        - set(attributes["component"], cache["component"]) where cache["component"] != nil
        - set(attributes["correlation_id"], cache["correlation_id"]) where cache["correlation_id"] != nil
        
        # Normalize log levels
        - set(attributes["severity_text"], "ERROR") where attributes["log.level"] matches "(?i)(error|err|fatal|panic)"
        - set(attributes["severity_text"], "WARN") where attributes["log.level"] matches "(?i)(warn|warning)"
        - set(attributes["severity_text"], "INFO") where attributes["log.level"] matches "(?i)(info|information)"
        - set(attributes["severity_text"], "DEBUG") where attributes["log.level"] matches "(?i)(debug|trace)"
        
        # Add timestamp if missing
        - set(time_unix_nano, Now()) where time_unix_nano == nil
        
        # Enrich with business context
        - set(attributes["log.source"], "application") where resource.attributes["service.name"] != nil
        - set(attributes["tenant_id"], resource.attributes["tenant.id"]) where resource.attributes["tenant.id"] != nil
        
        # Privacy protection
        - replace_pattern(body, "password=[^\\s]*", "password=***")
        - replace_pattern(body, "token=[^\\s]*", "token=***")
        - replace_pattern(body, "ssn=\\d{3}-\\d{2}-\\d{4}", "ssn=***-**-****")
        
        # Add log categorization
        - set(attributes["log.category"], "security") where IsMatch(body, "(?i)(login|logout|auth|unauthorized|forbidden)")
        - set(attributes["log.category"], "performance") where IsMatch(body, "(?i)(slow|timeout|latency|performance)")
        - set(attributes["log.category"], "error") where IsMatch(body, "(?i)(error|exception|failed|failure)")
      
      # Trace-specific transformations
      transform/traces:
        trace_statements:
        # Add trace-level attributes
        - set(attributes["trace.environment"], resource.attributes["deployment.environment"])
        - set(attributes["trace.cluster"], resource.attributes["cluster.name"])
        
        span_statements:
        # Normalize span names
        - set(name, Concat(["HTTP ", attributes["http.method"], " ", attributes["http.route"]], "")) where attributes["http.method"] != nil and attributes["http.route"] != nil
        
        # Add span categorization
        - set(attributes["span.category"], "http") where attributes["http.method"] != nil
        - set(attributes["span.category"], "database") where attributes["db.system"] != nil
        - set(attributes["span.category"], "messaging") where attributes["messaging.system"] != nil
        
        # Calculate span duration metrics
        - set(attributes["duration_ms"], Double(end_time_unix_nano - start_time_unix_nano) / 1000000.0)
        - set(attributes["duration_class"], "fast") where Double(end_time_unix_nano - start_time_unix_nano) / 1000000.0 < 100.0
        - set(attributes["duration_class"], "normal") where Double(end_time_unix_nano - start_time_unix_nano) / 1000000.0 >= 100.0 and Double(end_time_unix_nano - start_time_unix_nano) / 1000000.0 < 1000.0
        - set(attributes["duration_class"], "slow") where Double(end_time_unix_nano - start_time_unix_nano) / 1000000.0 >= 1000.0
        
        # Add error classification
        - set(attributes["error.type"], "client_error") where Int(attributes["http.status_code"]) >= 400 and Int(attributes["http.status_code"]) < 500
        - set(attributes["error.type"], "server_error") where Int(attributes["http.status_code"]) >= 500
        
        # Business logic attributes
        - set(attributes["business.transaction_type"], "purchase") where IsMatch(attributes["http.route"], ".*/(buy|purchase|checkout).*")
        - set(attributes["business.transaction_type"], "browse") where IsMatch(attributes["http.route"], ".*/(browse|search|catalog).*")
        
        # Remove sensitive span attributes
        - delete_key(attributes, "http.request.header.authorization")
        - delete_key(attributes, "user.email") where attributes["environment"] == "production"
        
        # Add geographical context
        - set(attributes["geo.country"], "US") where attributes["client.ip"] matches "^(192\\.168\\.|10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.).*"
    
    exporters:
      debug:
        verbosity: detailed
      
      # Example: Export different data types to different destinations
      # otlp/metrics:
      #   endpoint: "http://metrics-backend:4317"
      #   tls:
      #     insecure: true
      #
      # otlp/logs:
      #   endpoint: "http://logs-backend:4317"
      #   tls:
      #     insecure: true
      #
      # otlp/traces:
      #   endpoint: "http://traces-backend:4317"
      #   tls:
      #     insecure: true
    
    service:
      pipelines:
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, resource_transform, transform/metrics, batch]
          exporters: [debug]
        
        logs:
          receivers: [otlp]
          processors: [memory_limiter, resource_transform, transform/logs, batch]
          exporters: [debug]
        
        traces:
          receivers: [otlp]
          processors: [memory_limiter, resource_transform, transform/traces, batch]
          exporters: [debug]
```

Apply the collector:

```bash
kubectl apply -f otel-collector.yaml

# Wait for collector to be ready
kubectl wait --for=condition=available deployment/transform-collector-collector --timeout=300s
```

### Step 3: Deploy Sample Applications

Create applications that generate different types of telemetry data for transformation:

```yaml
# sample-apps.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-generator
  namespace: transform-demo
spec:
  replicas: 1
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
          OTEL_ENDPOINT="http://transform-collector-collector.transform-demo.svc:4318"
          
          while true; do
            # Send HTTP request metrics with various attributes
            curl -X POST ${OTEL_ENDPOINT}/v1/metrics \
              -H "Content-Type: application/json" \
              -d '{
                "resourceMetrics": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "shop-api"}
                    }, {
                      "key": "deployment.environment", 
                      "value": {"stringValue": "PRODUCTION"}
                    }, {
                      "key": "tenant.id",
                      "value": {"stringValue": "tenant-123"}
                    }]
                  },
                  "scopeMetrics": [{
                    "metrics": [{
                      "name": "http_requests",
                      "unit": "1",
                      "sum": {
                        "dataPoints": [{
                          "timeUnixNano": "'$(date +%s%N)'",
                          "asInt": "'$((RANDOM % 100 + 1))'",
                          "attributes": [{
                            "key": "status_code",
                            "value": {"stringValue": "200"}
                          }, {
                            "key": "method",
                            "value": {"stringValue": "GET"}
                          }, {
                            "key": "datacenter",
                            "value": {"stringValue": "us-west-1"}
                          }, {
                            "key": "user_id",
                            "value": {"stringValue": "user-'$((RANDOM % 1000))'"}
                          }, {
                            "key": "url",
                            "value": {"stringValue": "/api/products?token=secret123&page=1"}
                          }]
                        }],
                        "aggregationTemporality": 2,
                        "isMonotonic": true
                      }
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Sent metrics batch"
            sleep 10
          done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logs-generator
  namespace: transform-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: logs-generator
  template:
    metadata:
      labels:
        app: logs-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://transform-collector-collector.transform-demo.svc:4318"
          
          while true; do
            # Send structured and unstructured logs
            case $((RANDOM % 4)) in
              0)
                LOG_BODY='{"level":"info","component":"auth","correlation_id":"req-123","message":"User login successful","user_id":"user-456","password":"secret123"}'
                ;;
              1)
                LOG_BODY="level=error Authentication failed for user user-789 with token=abc123xyz"
                ;;
              2)
                LOG_BODY="WARN: Slow database query detected, duration=1500ms, query=SELECT * FROM users WHERE ssn=123-45-6789"
                ;;
              3)
                LOG_BODY="INFO [payment-service] Processing payment for order order-999, amount=$99.99"
                ;;
            esac
            
            curl -X POST ${OTEL_ENDPOINT}/v1/logs \
              -H "Content-Type: application/json" \
              -d '{
                "resourceLogs": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "payment-service"}
                    }, {
                      "key": "deployment.environment",
                      "value": {"stringValue": "production"}
                    }]
                  },
                  "scopeLogs": [{
                    "logRecords": [{
                      "timeUnixNano": "'$(date +%s%N)'",
                      "body": {
                        "stringValue": "'"$LOG_BODY"'"
                      }
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Sent log entry"
            sleep 8
          done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traces-generator
  namespace: transform-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: traces-generator
  template:
    metadata:
      labels:
        app: traces-generator
    spec:
      containers:
      - name: generator
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          OTEL_ENDPOINT="http://transform-collector-collector.transform-demo.svc:4318"
          
          while true; do
            TRACE_ID=$(openssl rand -hex 16)
            SPAN_ID=$(openssl rand -hex 8)
            START_TIME=$(date +%s%N)
            DURATION=$((RANDOM % 2000 + 100))
            END_TIME=$((START_TIME + DURATION * 1000000))
            
            curl -X POST ${OTEL_ENDPOINT}/v1/traces \
              -H "Content-Type: application/json" \
              -d '{
                "resourceSpans": [{
                  "resource": {
                    "attributes": [{
                      "key": "service.name",
                      "value": {"stringValue": "checkout-service"}
                    }, {
                      "key": "deployment.environment",
                      "value": {"stringValue": "staging"}
                    }]
                  },
                  "scopeSpans": [{
                    "spans": [{
                      "traceId": "'$TRACE_ID'",
                      "spanId": "'$SPAN_ID'",
                      "name": "process_payment",
                      "kind": 1,
                      "startTimeUnixNano": "'$START_TIME'",
                      "endTimeUnixNano": "'$END_TIME'",
                      "attributes": [{
                        "key": "http.method",
                        "value": {"stringValue": "POST"}
                      }, {
                        "key": "http.route",
                        "value": {"stringValue": "/api/v1/checkout/purchase"}
                      }, {
                        "key": "http.status_code",
                        "value": {"intValue": 200}
                      }, {
                        "key": "user.email",
                        "value": {"stringValue": "user@example.com"}
                      }, {
                        "key": "client.ip",
                        "value": {"stringValue": "192.168.1.100"}
                      }, {
                        "key": "db.system",
                        "value": {"stringValue": "postgresql"}
                      }]
                    }]
                  }]
                }]
              }' > /dev/null 2>&1
            
            echo "$(date): Sent trace span"
            sleep 12
          done
```

Apply sample applications:

```bash
kubectl apply -f sample-apps.yaml

# Wait for applications to be ready
kubectl wait --for=condition=available deployment/metrics-generator --timeout=300s
kubectl wait --for=condition=available deployment/logs-generator --timeout=300s  
kubectl wait --for=condition=available deployment/traces-generator --timeout=300s
```

### Step 4: Verify Transformations

Check that data transformations are working:

```bash
# Check collector logs for transformed data
kubectl logs deployment/transform-collector-collector -f --tail=100

# Look for specific transformations in metrics
kubectl logs deployment/transform-collector-collector --tail=1000 | grep -A 5 -B 5 "http_requests_total"

# Look for log transformations
kubectl logs deployment/transform-collector-collector --tail=1000 | grep -A 10 -B 10 "severity_text"

# Look for trace transformations  
kubectl logs deployment/transform-collector-collector --tail=1000 | grep -A 10 -B 10 "span.category"
```

### Step 5: Run Verification Script

```bash
# Create verification script
cat > check_transformations.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking Transform processor functionality..."

# Get collector pod name
COLLECTOR_POD=$(kubectl get pods -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}')

if [ -z "$COLLECTOR_POD" ]; then
    echo "ERROR: No collector pod found"
    exit 1
fi

echo "Using collector pod: $COLLECTOR_POD"

# Wait for transformations to be processed
echo "Waiting for data transformation..."
sleep 60

echo "Checking metric transformations..."

# Check metric name transformations
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "http_requests_total"
if [ $? -eq 0 ]; then
    echo "✓ Metric name transformation detected (http_requests -> http_requests_total)"
else
    echo "✗ Metric name transformation not found"
fi

# Check attribute additions
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "business_unit"
if [ $? -eq 0 ]; then
    echo "✓ Business context attributes added"
else
    echo "✗ Business context attributes not found"
fi

# Check data sanitization
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "token=\*\*\*"
if [ $? -eq 0 ]; then
    echo "✓ Sensitive data sanitization working"
else
    echo "✗ Sensitive data sanitization not found"
fi

echo "Checking log transformations..."

# Check log level normalization
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "severity_text.*ERROR"
if [ $? -eq 0 ]; then
    echo "✓ Log level normalization detected"
else
    echo "✗ Log level normalization not found"
fi

# Check log categorization
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "log.category"
if [ $? -eq 0 ]; then
    echo "✓ Log categorization working"
else
    echo "✗ Log categorization not found"
fi

echo "Checking trace transformations..."

# Check span categorization
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "span.category"
if [ $? -eq 0 ]; then
    echo "✓ Span categorization detected"
else
    echo "✗ Span categorization not found"
fi

# Check duration calculations
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "duration_ms"
if [ $? -eq 0 ]; then
    echo "✓ Duration calculations working"
else
    echo "✗ Duration calculations not found"
fi

# Check resource-level transformations
kubectl logs $COLLECTOR_POD --tail=2000 | grep -q "cluster.name.*transform-demo-cluster"
if [ $? -eq 0 ]; then
    echo "✓ Resource attribute transformations working"
else
    echo "✗ Resource attribute transformations not found"
fi

echo "Transform processor verification completed!"
EOF

chmod +x check_transformations.sh
./check_transformations.sh
```

## 🔧 Advanced Transformation Patterns

### Conditional Transformations

Apply transformations based on conditions:

```yaml
processors:
  transform:
    metric_statements:
    - context: datapoint
      statements:
      # Apply different transformations based on service
      - set(attributes["tier"], "frontend") where resource.attributes["service.name"] matches ".*ui.*"
      - set(attributes["tier"], "backend") where resource.attributes["service.name"] matches ".*api.*"
      - set(attributes["tier"], "data") where resource.attributes["service.name"] matches ".*(db|cache|queue).*"
      
      # Different alert thresholds by environment
      - set(attributes["alert.threshold"], "0.95") where resource.attributes["environment"] == "production"
      - set(attributes["alert.threshold"], "0.80") where resource.attributes["environment"] == "staging"
```

### Complex Data Extraction

Extract data from complex structures:

```yaml
processors:
  transform:
    log_statements:
    # Extract from nested JSON
    - merge_maps(cache, ParseJSON(body), "upsert") where IsMatch(body, "^{.*}$")
    - set(attributes["request.id"], cache["request"]["id"]) where cache["request"]["id"] != nil
    - set(attributes["user.session"], cache["user"]["session"]["id"]) where cache["user"]["session"]["id"] != nil
    
    # Extract from structured logs
    - merge_maps(cache, ExtractPatterns(body, "user=(?P<user>\\w+) action=(?P<action>\\w+) result=(?P<result>\\w+)"), "upsert")
    - set(attributes["user.name"], cache["user"]) where cache["user"] != nil
    - set(attributes["user.action"], cache["action"]) where cache["action"] != nil
```

### Performance Optimizations

Optimize transformations for high-throughput:

```yaml
processors:
  transform:
    # Limit expensive operations
    metric_statements:
    - context: datapoint
      statements:
      # Only transform high-priority metrics
      - set(attributes["enriched"], "true") where resource.attributes["service.name"] matches ".*(critical|payment|auth).*"
      
      # Batch similar transformations
      - set(attributes["normalized"], "true")
      - set(attributes["processed_at"], Now())
```

## 🔍 Monitoring Transform Performance

### Key Metrics to Monitor

```bash
# Transform processor performance
otelcol_processor_transform_operations_total
otelcol_processor_transform_duration_seconds

# Memory usage during transformation
otelcol_process_memory_rss

# Data flow through pipelines
otelcol_processor_batch_batch_send_size_sum
```

### Performance Tuning

```yaml
processors:
  # Optimize batch processing
  batch:
    timeout: 1s
    send_batch_size: 2048
  
  # Memory management
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
```

## 🚨 Troubleshooting

### Transformation Not Applied

```bash
# Check processor order in pipeline
kubectl get opentelemetrycollector transform-collector -o yaml | grep -A 10 "processors:"

# Check for syntax errors in transform statements
kubectl logs deployment/transform-collector-collector | grep -i "transform\|error\|failed"

# Verify data is reaching the processor
kubectl logs deployment/transform-collector-collector | grep -i "received"
```

### Performance Issues

```bash
# Check processing latency
kubectl logs deployment/transform-collector-collector | grep -i "duration\|latency"

# Monitor memory usage
kubectl top pods -l app.kubernetes.io/component=opentelemetry-collector

# Check for bottlenecks
kubectl describe pod -l app.kubernetes.io/component=opentelemetry-collector | grep -A 5 "Limits\|Requests"
```

### Syntax Errors

```bash
# Validate transform expressions
kubectl logs deployment/transform-collector-collector | grep -i "expression\|syntax\|parse"

# Check specific statement failures
kubectl logs deployment/transform-collector-collector | grep -A 5 -B 5 "statement.*failed"
```

## 🔐 Security Considerations

1. **Data Sanitization**: Configure data sanitization for sensitive information
2. **Access Control**: Limit access to transformation configurations
3. **Audit Trail**: Log transformation changes for compliance
4. **Performance Impact**: Monitor resource usage during transformations

## 📚 Related Patterns

- [filterprocessor](../filterprocessor/) - For selective data processing
- [groupbyattrsprocessor](../groupbyattrsprocessor/) - For data aggregation
- [prometheusremotewriteexporter](../prometheusremotewriteexporter/) - For transformed metrics export

## 🧹 Cleanup

```bash
# Remove sample applications
kubectl delete deployment metrics-generator logs-generator traces-generator

# Remove OpenTelemetry collector
kubectl delete opentelemetrycollector transform-collector

# Remove namespace
kubectl delete namespace transform-demo
``` 