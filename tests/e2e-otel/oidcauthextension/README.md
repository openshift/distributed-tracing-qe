# OIDC Auth Extension - Secure Collector Communication

This blueprint demonstrates how to use the OpenTelemetry OIDC Authentication Extension to secure collector-to-collector communication using industry-standard OAuth2/OIDC protocols. This demonstrates authenticated and authorized telemetry data flow.

## 🎯 Use Case

- **Secure Communication**: Authenticate collector-to-collector data transmission
- **Zero Trust Architecture**: Implement authentication for all telemetry data flows
- **Multi-Tenant Systems**: Isolate telemetry data by tenant using authentication
- **Compliance Scenarios**: Demonstrate security and compliance patterns
- **Identity Integration**: Integrate with existing OAuth2/OIDC identity providers

## 📋 What You'll Deploy

- **Hydra OIDC Provider**: OAuth2/OIDC server for authentication and authorization
- **OIDC Server Collector**: Collector with OIDC authentication extension (receiver side)
- **OAuth2 Client Collector**: Collector with OAuth2 client extension (sender side)
- **TLS Certificates**: Secure communication with custom certificate authority
- **Trace Generator**: Sample application to test authenticated data flow

## 🚀 Step-by-Step Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- OpenTelemetry Operator installed
- `kubectl` or `oc` CLI tool configured
- `openssl` for certificate generation
- Understanding of OAuth2/OIDC concepts

### Step 1: Create Namespace

```bash
# Create dedicated namespace for testing
kubectl create namespace oidcauthextension-demo

# Set as current namespace
kubectl config set-context --current --namespace=oidcauthextension-demo
```

### Step 2: Deploy Hydra OIDC Provider

Create the Hydra OAuth2/OIDC server:

```yaml
# install-hydra.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hydra
  namespace: oidcauthextension-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hydra
  template:
    metadata:
      labels:
        app: hydra
    spec:
      containers:
      - name: hydra
        image: docker.io/oryd/hydra:v2.2.0
        command: ["hydra", "serve", "all", "--dev", "--sqa-opt-out"]
        env:
        - name: DSN
          value: memory
        - name: SECRETS_SYSTEM
          value: saf325iouepdsg8574nb39afdu
        - name: URLS_SELF_ISSUER
          value: http://hydra:4444
        - name: STRATEGIES_ACCESS_TOKEN
          value: jwt
        ports:
        - containerPort: 4444
          name: public
        - containerPort: 4445
          name: internal
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
  name: hydra
  namespace: oidcauthextension-demo
spec:
  selector:
    app: hydra
  ports:
  - name: public
    port: 4444
    targetPort: public
  - name: internal
    port: 4445
    targetPort: internal
```

Apply the Hydra deployment:

```bash
kubectl apply -f install-hydra.yaml

# Wait for Hydra to be ready
kubectl wait --for=condition=available deployment/hydra --timeout=300s
```

### Step 3: Generate TLS Certificates

Create TLS certificates for secure communication:

```bash
# Create certificate generation script
cat > generate_certs.sh << 'EOF'
#!/bin/bash
set -e

echo "Generating TLS certificates for OIDC authentication..."

# Create temporary directory for certificates
CERT_DIR="/tmp/oidcauth-certs"
rm -rf "$CERT_DIR"
mkdir -p "$CERT_DIR"

# Set certificate subject
CERT_SUBJECT="/C=US/ST=California/L=San Francisco/O=OpenTelemetry/CN=oidcauth-demo"

# Create OpenSSL configuration with SANs
openssl_config="$CERT_DIR/openssl.cnf"
cat <<EOL > "$openssl_config"
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = v3_req

[ req_distinguished_name ]
countryName                = Country Name (2 letter code)
countryName_default        = US
stateOrProvinceName        = State or Province Name (full name)
stateOrProvinceName_default= California
localityName               = Locality Name (eg, city)
localityName_default       = San Francisco
organizationName           = Organization Name (eg, company)
organizationName_default   = OpenTelemetry
commonName                 = Common Name (eg, your name or your server's hostname)
commonName_max             = 64

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = oidcauth-demo
DNS.2 = oidc-server-collector
DNS.3 = oidc-server-collector.oidcauthextension-demo.svc.cluster.local
DNS.4 = localhost
IP.1 = 127.0.0.1
EOL

# Generate private key
openssl genpkey -algorithm RSA -out "$CERT_DIR/server.key"

# Create certificate signing request
openssl req -new -key "$CERT_DIR/server.key" -out "$CERT_DIR/server.csr" \
  -subj "$CERT_SUBJECT" -config "$openssl_config"

# Generate self-signed certificate
openssl x509 -req -days 365 -in "$CERT_DIR/server.csr" \
  -signkey "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" \
  -extensions v3_req -extfile "$openssl_config"

# Generate CA certificate (same as server for demo purposes)
openssl req -new -x509 -days 365 -key "$CERT_DIR/server.key" \
  -out "$CERT_DIR/ca.crt" -subj "$CERT_SUBJECT"

echo "✅ Certificates generated successfully"

# Remove existing ConfigMap if it exists
kubectl delete configmap oidcauth-certs -n oidcauthextension-demo 2>/dev/null || true

# Create Kubernetes ConfigMap with certificates
kubectl create configmap oidcauth-certs -n oidcauthextension-demo \
  --from-file=server.crt="$CERT_DIR/server.crt" \
  --from-file=server.key="$CERT_DIR/server.key" \
  --from-file=ca.crt="$CERT_DIR/ca.crt"

echo "✅ ConfigMap created with TLS certificates"

# Cleanup temporary files
rm -rf "$CERT_DIR"
EOF

chmod +x generate_certs.sh
./generate_certs.sh
```

### Step 4: Set Up OAuth2 Client in Hydra

Create OAuth2 client configuration:

```yaml
# setup-hydra.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: setup-hydra
  namespace: oidcauthextension-demo
spec:
  template:
    spec:
      containers:
      - name: setup-hydra
        image: curlimages/curl:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "Setting up OAuth2 client in Hydra..."
          
          # Wait for Hydra to be ready
          until curl -s http://hydra:4444/.well-known/openid_configuration; do
            echo "Waiting for Hydra to be ready..."
            sleep 5
          done
          
          # Create OAuth2 client
          client_id=tenant1-oidc-client
          client_secret=ZXhhbXBsZS1hcHAtc2VjcmV0  # base64 encoded "example-app-secret"
          
          echo "Creating OAuth2 client: $client_id"
          
          curl -v -X POST \
            -H "Content-Type: application/json" \
            -d '{
              "audience": ["'$client_id'"],
              "client_id": "'$client_id'",
              "client_secret": "'$client_secret'",
              "grant_types": ["client_credentials"],
              "token_endpoint_auth_method": "client_secret_basic",
              "scope": "openid"
            }' \
            http://hydra:4445/admin/clients
          
          echo "✅ OAuth2 client setup completed"
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

Apply the OAuth2 client setup:

```bash
kubectl apply -f setup-hydra.yaml

# Wait for the setup job to complete
kubectl wait --for=condition=complete job/setup-hydra --timeout=300s

# Check setup job logs
kubectl logs job/setup-hydra
```

### Step 5: Deploy OIDC Server Collector

Create the collector that validates OIDC tokens:

```yaml
# install-otel-oidc-server.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: oidc-server
  namespace: oidcauthextension-demo
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  
  # Mount TLS certificates
  volumeMounts:
  - mountPath: /certs
    name: oidcauth-certs
  volumes:
  - configMap:
      name: oidcauth-certs
    name: oidcauth-certs
  
  config:
    extensions:
      # OIDC authentication extension
      oidc:
        issuer_url: http://hydra:4444
        audience: tenant1-oidc-client
        
        # Optional: Additional OIDC configuration
        # client_id: tenant1-oidc-client
        # username_claim: sub
        # groups_claim: groups
    
    receivers:
      # OTLP receiver with OIDC authentication
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
            tls:
              cert_file: /certs/server.crt
              key_file: /certs/server.key
            auth:
              authenticator: oidc
          http:
            endpoint: 0.0.0.0:4318
            tls:
              cert_file: /certs/server.crt
              key_file: /certs/server.key
            auth:
              authenticator: oidc
    
    processors:
      # Batch processor
      batch:
        timeout: 5s
        send_batch_size: 1024
      
      # Add authentication metadata
      attributes:
        actions:
        - key: auth.method
          value: "oidc"
          action: insert
        - key: auth.issuer
          value: "hydra"
          action: insert
    
    exporters:
      # Debug exporter to see authenticated traces
      debug:
        verbosity: detailed
      
      # Optional: Forward to downstream systems
      # otlp:
      #   endpoint: "downstream-collector:4317"
      #   tls:
      #     insecure: true
    
    service:
      # Enable OIDC extension
      extensions: [oidc]
      
      pipelines:
        traces:
          receivers: [otlp]
          processors: [attributes, batch]
          exporters: [debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8888
```

Apply the OIDC server collector:

```bash
kubectl apply -f install-otel-oidc-server.yaml

# Wait for the server collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=oidc-server --timeout=300s
```

### Step 6: Deploy OAuth2 Client Collector

Create the collector that obtains and uses OAuth2 tokens:

```yaml
# install-otel-oidc-client.yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: oidc-client
  namespace: oidcauthextension-demo
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  
  # Mount TLS certificates
  volumes:
  - name: oidcauth-certs
    configMap: 
      name: oidcauth-certs
  volumeMounts:
  - name: oidcauth-certs
    mountPath: /certs
  
  config:
    extensions:
      # OAuth2 client extension
      oauth2client:
        client_id: tenant1-oidc-client
        client_secret: ZXhhbXBsZS1hcHAtc2VjcmV0  # base64 encoded "example-app-secret"
        token_url: http://hydra:4444/oauth2/token
        
        # Additional OAuth2 parameters
        endpoint_params:
          audience: tenant1-oidc-client
        
        # Optional: Token caching
        # timeout: 30s
        # retry:
        #   max_attempts: 3
        #   initial_interval: 1s
    
    receivers:
      # OTLP receiver for incoming traces
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      # Batch processor
      batch:
        timeout: 5s
        send_batch_size: 1024
      
      # Add client metadata
      attributes:
        actions:
        - key: client.type
          value: "oauth2"
          action: insert
        - key: client.authenticated
          value: "true"
          action: insert
    
    exporters:
      # OTLP exporter with OAuth2 authentication
      otlp:
        endpoint: oidc-server-collector:4317
        tls:
          insecure: false
          ca_file: /certs/ca.crt
        auth:
          authenticator: oauth2client
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
      
      # Debug exporter for troubleshooting
      debug:
        verbosity: basic
    
    service:
      # Enable OAuth2 client extension
      extensions: [oauth2client]
      
      pipelines:
        traces:
          receivers: [otlp]
          processors: [attributes, batch]
          exporters: [otlp, debug]
      
      telemetry:
        logs:
          level: info
        metrics:
          address: 0.0.0.0:8889
```

Apply the OAuth2 client collector:

```bash
kubectl apply -f install-otel-oidc-client.yaml

# Wait for the client collector to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=oidc-client --timeout=300s
```

### Step 7: Generate Test Traces

Create traces to test the authenticated communication:

```yaml
# generate-traces.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: generate-traces
  namespace: oidcauthextension-demo
spec:
  template:
    spec:
      containers:
      - name: telemetrygen
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - traces
        - --otlp-endpoint=oidc-client-collector:4317
        - --otlp-insecure=true
        - --traces=10
        - --span-name=lets-go
        - --service=authenticated-service
        - --otlp-attributes=auth.test="true"
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
  name: generate-traces-2
  namespace: oidcauthextension-demo
spec:
  template:
    spec:
      containers:
      - name: telemetrygen
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.129.0
        command: ["./telemetrygen"]
        args:
        - traces
        - --otlp-endpoint=oidc-client-collector:4317
        - --otlp-insecure=true
        - --traces=10
        - --span-name=okey-dokey
        - --service=secure-service
        - --otlp-attributes=auth.verified="true"
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
kubectl logs job/generate-traces -f
kubectl logs job/generate-traces-2 -f
```

### Step 8: Verify Authenticated Communication

Check that traces are flowing through the authenticated pipeline:

```bash
# Check OIDC server collector logs for authenticated traces
kubectl logs -l app.kubernetes.io/name=oidc-server --tail=100

# Check OAuth2 client collector logs
kubectl logs -l app.kubernetes.io/name=oidc-client --tail=100

# Check Hydra logs for token requests
kubectl logs deployment/hydra --tail=50
```

### Step 9: Run Verification Script

Create and run verification script:

```bash
# Create verification script
cat > check_logs.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking OIDC authentication extension functionality..."

# Define the label selector and namespace
LABEL_SELECTOR="app.kubernetes.io/name=oidc-server"
NAMESPACE=${NAMESPACE:-oidcauthextension-demo}

# Define expected trace patterns
EXPECTED_PATTERNS=(
    "Name           : lets-go"
    "Name           : okey-dokey"
    "Trace ID"
    "Parent ID"
    "auth.method"
)

# Get server collector pods
PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "❌ No OIDC server collector pods found"
    exit 1
fi

echo "Found ${#PODS[@]} OIDC server collector pod(s): ${PODS[*]}"

# Initialize flags for tracking found patterns
declare -A found_flags
for pattern in "${EXPECTED_PATTERNS[@]}"; do
    found_flags["$pattern"]=false
done

max_attempts=60  # Wait up to 5 minutes
attempt=0

echo "Waiting for authenticated traces to appear..."

# Keep checking until all patterns are found or timeout
while [ $attempt -lt $max_attempts ]; do
    all_found=true
    
    # Check each pod for expected patterns
    for POD in "${PODS[@]}"; do
        LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=200 2>/dev/null || echo "")
        
        # Search for each expected pattern
        for PATTERN in "${EXPECTED_PATTERNS[@]}"; do
            if [ "${found_flags[$PATTERN]}" = false ] && echo "$LOGS" | grep -q -- "$PATTERN"; then
                echo "✅ \"$PATTERN\" found in $POD"
                found_flags["$PATTERN"]=true
            fi
        done
    done
    
    # Check if all patterns found
    for PATTERN in "${EXPECTED_PATTERNS[@]}"; do
        if [ "${found_flags[$PATTERN]}" = false ]; then
            all_found=false
            break
        fi
    done
    
    if [ "$all_found" = true ]; then
        break
    fi
    
    echo "  Attempt $((attempt+1)): Waiting for more traces..."
    sleep 5
    ((attempt++))
done

# Final verification
missing_patterns=()
for PATTERN in "${EXPECTED_PATTERNS[@]}"; do
    if [ "${found_flags[$PATTERN]}" = false ]; then
        missing_patterns+=("$PATTERN")
    fi
done

if [ ${#missing_patterns[@]} -eq 0 ]; then
    echo "🎉 OIDC authentication extension verification completed successfully!"
    echo "✅ All expected authenticated traces found"
    echo "✅ OAuth2/OIDC authentication is working correctly"
else
    echo "❌ OIDC authentication verification failed"
    echo "Missing patterns: ${missing_patterns[*]}"
    exit 1
fi
EOF

chmod +x check_logs.sh
./check_logs.sh
```

## 🔧 Advanced Configuration

### Multiple Audiences

Configure OIDC for multiple audiences:

```yaml
extensions:
  oidc:
    issuer_url: http://hydra:4444
    audience: ["tenant1-oidc-client", "tenant2-oidc-client"]
    username_claim: sub
    groups_claim: groups
```

### Custom Claims Validation

Validate custom JWT claims:

```yaml
extensions:
  oidc:
    issuer_url: http://hydra:4444
    audience: tenant1-oidc-client
    attribute: "custom_claim"
    allowed_values: ["value1", "value2"]
```

### External OIDC Providers

Use external OIDC providers like Keycloak, Auth0, or Azure AD:

```yaml
extensions:
  oidc:
    issuer_url: https://your-keycloak.example.com/auth/realms/your-realm
    audience: otel-collector
    username_claim: preferred_username
    groups_claim: groups
```

### Token Caching and Refresh

Configure token caching for performance:

```yaml
extensions:
  oauth2client:
    client_id: tenant1-oidc-client
    client_secret: your-secret
    token_url: http://hydra:4444/oauth2/token
    timeout: 30s
    retry:
      max_attempts: 3
      initial_interval: 1s
      max_interval: 10s
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

```bash
# Check OIDC provider health
kubectl port-forward svc/hydra 4444:4444 &
curl http://localhost:4444/.well-known/openid_configuration

# Check certificate validity
kubectl get configmap oidcauth-certs -o jsonpath='{.data.server\.crt}' | openssl x509 -noout -dates

# Check collector authentication status
kubectl logs -l app.kubernetes.io/name=oidc-server | grep -i "auth\|oidc"
```

### Common Issues

**Issue: Authentication failed**
```bash
# Check OIDC configuration
kubectl logs -l app.kubernetes.io/name=oidc-server | grep -i "oidc.*error"

# Verify OAuth2 client configuration
kubectl logs -l app.kubernetes.io/name=oidc-client | grep -i "oauth2.*error"

# Check Hydra client setup
kubectl logs deployment/hydra | grep -i "client"
```

**Issue: Certificate errors**
```bash
# Verify certificate configuration
kubectl describe configmap oidcauth-certs

# Check certificate-hostname matching
kubectl logs -l app.kubernetes.io/name=oidc-client | grep -i "certificate\|tls"
```

**Issue: Token validation failed**
```bash
# Check token issuer and audience
kubectl port-forward svc/hydra 4444:4444 &
curl -X POST http://localhost:4444/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=tenant1-oidc-client&client_secret=ZXhhbXBsZS1hcHAtc2VjcmV0"

# Verify OIDC configuration matches
kubectl get opentelemetrycollector oidc-server -o yaml | grep -A 5 oidc
```

### Performance Monitoring

```bash
# Monitor authentication latency
kubectl logs -l app.kubernetes.io/name=oidc-client | grep -i "token.*latency"

# Check token refresh frequency
kubectl logs -l app.kubernetes.io/name=oidc-client | grep -i "token.*refresh"
```

## 📊 Security Configuration Examples

### Secret Management

Use Kubernetes secrets for sensitive data:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-client-secret
type: Opaque
stringData:
  client_secret: your-actual-secret

# Reference in collector config
extensions:
  oauth2client:
    client_secret: ${env:OAUTH2_CLIENT_SECRET}
```

### Certificate Rotation

Implement certificate rotation:

```bash
# Create new certificates
./generate_certs.sh

# Update running collectors
kubectl rollout restart deployment oidc-server oidc-client
```

### Network Policies

Restrict network access:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: oidc-auth-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: oidc-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: oidc-client
    ports:
    - protocol: TCP
      port: 4317
```

## 🔐 Security Considerations

1. **Certificate Security**: Configure proper certificate authorities
2. **Secret Management**: Store client secrets securely using Kubernetes secrets
3. **Token Scope**: Limit OAuth2 token scopes to minimum required permissions
4. **Network Security**: Use network policies to restrict access
5. **Audit Logging**: Enable audit logging for authentication events

## 📚 Related Patterns

- [awsxrayexporter](../awsxrayexporter/) - For authenticated AWS integrations
- [transformprocessor](../transformprocessor/) - For adding authentication metadata
- [routingconnector](../routingconnector/) - For tenant-based routing

## 🧹 Cleanup

```bash
# Remove trace generation jobs
kubectl delete job generate-traces generate-traces-2

# Remove OAuth2 setup job
kubectl delete job setup-hydra

# Remove OpenTelemetry collectors
kubectl delete opentelemetrycollector oidc-server oidc-client

# Remove Hydra deployment
kubectl delete deployment hydra
kubectl delete service hydra

# Remove certificates
kubectl delete configmap oidcauth-certs

# Remove namespace
kubectl delete namespace oidcauthextension-demo
```

## 📖 Additional Resources

- [OpenTelemetry OIDC Auth Extension Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/extension/oidcauthextension)
- [OpenTelemetry OAuth2 Client Extension Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/extension/oauth2clientauthextension)
- [OAuth 2.0 and OpenID Connect Overview](https://oauth.net/2/)
- [Ory Hydra Documentation](https://www.ory.sh/docs/hydra/) 