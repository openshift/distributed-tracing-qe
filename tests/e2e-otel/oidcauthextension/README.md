# OpenTelemetry OIDC Authentication Extension Test

This test demonstrates the OpenTelemetry OIDC Authentication Extension configuration for securing collector-to-collector communication using OAuth2/OIDC protocols.

## 🎯 What This Test Does

The test validates that the OIDC Authentication Extension can:
- Secure OTLP communication between collectors using OIDC authentication
- Use Hydra as an OAuth2/OIDC provider for token management
- Configure server-side OIDC authentication for incoming requests
- Configure client-side OAuth2 authentication for outgoing requests
- Handle TLS certificate validation for secure communication

## 📋 Test Resources

### 1. Hydra OIDC Provider
The test deploys Ory Hydra as the OAuth2/OIDC provider for authentication services.

### 2. Certificate Generation
The test generates TLS certificates using the `generate_certs.sh` script and creates a ConfigMap with the certificates.

### 3. OIDC Server Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: chainsaw-oidc-server
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  volumeMounts:
  - mountPath: /certs
    name: chainsaw-certs
  volumes:
  - configMap:
      name: chainsaw-certs
    name: chainsaw-certs
  config: |
    extensions:
      oidc:
        issuer_url: http://hydra:4444
        audience: tenant1-oidc-client

    receivers:
      otlp:
        protocols:
          grpc:
            tls:
              cert_file: /certs/server.crt
              key_file: /certs/server.key
            auth:
              authenticator: oidc

    processors:

    exporters:
      debug:
        verbosity: detailed

    service:
      extensions: [oidc]
      pipelines:
        traces:
          receivers: [otlp]
          processors: []
          exporters: [debug]
```

### 4. OIDC Client Collector
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: chainsaw-oidc-client
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  volumes:
    - name: chainsaw-certs
      configMap: 
        name: chainsaw-certs
  volumeMounts:
    - name: chainsaw-certs
      mountPath: /certs
  config: |
    extensions:
      oauth2client:
        client_id: tenant1-oidc-client
        client_secret: ZXhhbXBsZS1hcHAtc2VjcmV0
        endpoint_params:
          audience: tenant1-oidc-client
        token_url: http://hydra:4444/oauth2/token

    receivers:
      otlp:
        protocols:
          grpc:
          http:

    processors:

    exporters:
      otlp:
        endpoint: chainsaw-oidc-server-collector:4317
        tls:
          insecure: false
          ca_file: /certs/ca.crt
        auth:
          authenticator: oauth2client

    service:
      extensions: [oauth2client]
      pipelines:
        traces:
          receivers: [otlp]
          processors: []
          exporters: [otlp]
```

### 5. Trace Generator
The test generates traces that are sent to the client collector, which then forwards them to the server collector using OIDC authentication.

## 🚀 Test Steps

1. **Install Hydra** - Deploy Ory Hydra OAuth2/OIDC provider
2. **Setup OAuth2 Client** - Create OAuth2 client configuration in Hydra
3. **Generate Certificates** - Create TLS certificates and ConfigMap for secure communication
4. **Create OIDC Server Collector** - Deploy server collector with OIDC authentication extension
5. **Create OIDC Client Collector** - Deploy client collector with OAuth2 client extension
6. **Generate Traces** - Send traces to test the authenticated communication
7. **Wait for Processing** - Allow 60 seconds for trace processing
8. **Check Traces** - Verify traces are received by the server collector

## 🔍 Authentication Flow

### OIDC Server Configuration:
- **Extension**: `oidc`
- **Issuer URL**: `http://hydra:4444`
- **Audience**: `tenant1-oidc-client`
- **TLS**: Uses server certificate for secure communication
- **Authentication**: Validates incoming OIDC tokens

### OAuth2 Client Configuration:
- **Extension**: `oauth2client`
- **Client ID**: `tenant1-oidc-client`
- **Client Secret**: `ZXhhbXBsZS1hcHAtc2VjcmV0` (base64 encoded)
- **Token URL**: `http://hydra:4444/oauth2/token`
- **Audience**: `tenant1-oidc-client`
- **TLS**: Uses CA certificate for server validation

### Certificate Management:
- **CA Certificate**: Used for TLS validation
- **Server Certificate**: Used by server collector for TLS termination
- **Certificate Storage**: Mounted from ConfigMap to both collectors

## 🔍 Verification

The test verification confirms that:
- Hydra OIDC provider is running and configured
- OAuth2 client is properly registered with Hydra
- TLS certificates are generated and mounted correctly
- OIDC server collector can authenticate incoming requests
- OAuth2 client collector can obtain and use access tokens
- Traces are successfully transmitted with proper authentication
- Server collector receives and processes the authenticated traces

## 🧹 Cleanup

The test runs in the `chainsaw-oidcauthextension` namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses fixed namespace (`chainsaw-oidcauthextension`) for OIDC authentication setup
- Demonstrates end-to-end OAuth2/OIDC authentication between collectors
- Integrates TLS security with OIDC authentication for comprehensive security
- Uses Hydra as a standard-compliant OAuth2/OIDC provider
- Shows both server-side authentication validation and client-side token acquisition
- Validates secure collector-to-collector communication patterns 