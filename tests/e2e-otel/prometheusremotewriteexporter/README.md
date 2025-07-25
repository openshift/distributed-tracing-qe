# OpenTelemetry Prometheus Remote Write Exporter Test

This test demonstrates the OpenTelemetry Prometheus Remote Write exporter configuration for sending metrics to Prometheus.

## 🎯 What This Test Does

The test validates that the Prometheus Remote Write exporter can:
- Export metrics to Prometheus using the remote write protocol
- Use TLS authentication with custom CA certificates
- Convert OpenTelemetry metrics to Prometheus format
- Send metrics over HTTPS with proper certificate validation

## 📋 Test Resources

### 1. Prometheus CA Certificate Secret
```yaml
apiVersion: v1
data:
  ca.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUZCekNDQXUrZ0F3SUJBZ0lVSm9wazRvUkNqU05NSnFJaXFYb2k2cmxneWlBd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0V6RVJNQThHQTFVRUF3d0lUWGxFWlc1dlEwRXdIaGNOTWpRd09ERTVNVEF4T0RFd1doY05NelF3T0RFMwpNVEF4T0RFd1dqQVRNUkV3RHdZRFZRUUREQWhOZVVSbGJXOURRVENDQWlJd0RRWUpLb1pJaHZjTkFRRUJCUUFECmdnSVBBRENDQWdvQ2dnSUJBS3A3UTJPOVI5VlZwUnVkV2pueEcyeWNNcVEyZGV1dDU1VUxTcjRxTCsvSE9QSUEKTUFKRUxqbGtDdTFCRTBiTmV4L3hRbktnVDUvVVlxN3dyV3NRWC9VSW9wU2d1WGxaMy9JTnRuZ2lzbkhFT09ZSwprUlFuWDdQRHF3OG81V1ZoZEpNaStoQ3ZzNnRZbnRlbmdZcCtZNVFKSFdPbVBSUGxvMllOWHNiMG4rdGVwNXVqCm9wU3BzNTNYSmtRc1dvNWVtTktzMUNUdkdackVkZk95QWFIS0xjMlpYMGFQUmRLNEdpOGpzMWk5dk13amhtS3EKUUc2SVJXbUx4Z3N4dmxLbG1HMDNxRnY5cjI4QktGeU9HSUN0ZmVRQXRSaUhJa0lJSmQyUG9lUFN5dkxqRnJWRwpiRyswTnkvZEorQXpydFUrYnRZeVBMSmVqTHJubmc2enc0amp4aXd1bXYxdXFiMlRha29JaVNOZjZabFlnZ2U4CkdXb1hsYUlmR3hINVpyMmYvazE2cnRxNVM3VVNFQko5cHB6RU9NVjUwL2xrOGxWVEpsNmw3S2lBczRhZnZ2aHAKZHFoU3htN3pVRmREYy9xZlJ5NTZ5ZFJpYmI2Z0lwb25Ib3JrNTRDcld6K2hBaGI2ckV4eG5vSTVmSmZiM0UxNQo4VUw2OWx3TGV0a3B0dDhsdlAvSVFnRDRpU0FhakcrYVYvYnJlSjV6ZTRkL3lyZWNtWTVsYTd3T3ExNFVQOVdQCnZEWlBTdUgyZEhuV0RkTDM3YnRKaVZ2dWpTaUtFSm9tTGE3eXdKTG1hL2FmeTEybXhmcVV3ZWpKaDQrWitvUW4Ka0Q4SEIyM283SklJekU5TCtuelo1bnRxSkhsb1NJa3c1d0twVmNybUo5NkxuWHdLcmVMZnlpNXZJenYvQWdNQgpBQUdqVXpCUk1CMEdBMVVkRGdRV0JCUUtJbE4rZXZlYXg2NU5hRmVOWlhOcU40WHhkREFmQmdOVkhTTUVHREFXCmdCUUtJbE4rZXZlYXg2NU5hRmVOWlhOcU40WHhkREFQQmdOVkhSTUJBZjhFQlRBREFRSC9NQTBHQ1NxR1NJYjMKRFFFQkN3VUFBNElDQVFCQ2R1TytvWDNSQkpJZUR4TDVURnpCcTZQTkRIYXJMeFErSTFVekhUNktUTTl4S3hQZgpSWkFRdmU4ZlE0a1hMdnAwL3h1MEZaZU9LZUh0MEFHS09CaGZYcTA4eUZCRys3a0hwSzhWUWtnUmtRT0w5ZkJEClRHbVdHZld5bXBWYTEvM1pBaUdNVTYzVmF5UVpCZnp5Nm0yR3NscVdLSEZYRXhSak1BaUZUcjZoWTJSSDIycTUKNGY4alZ4dUMyWCtqVHZ2N0tIMGVqUXp6SERqYlpGWitsbFdyMnYzSkY3Z21XUENtV1lTVHF3VTlkSzY4QnhvNgpwY0cxTDRiazF6Z0wvMkhCOVR3ZG8xYy9xT1N6amE0eVc5dkF0TFBGNm5MTjFTR1lCQlh2UTlZc1JCTklHb3lxCk1DUXJjbFRrKy9mL0R5WE1idVYvRmFmWlp2R3ZPd1phOXlaQUhCM2c3VEZTUzBTdnhLSnMzaXJrLzV1NnRjWVAKTXZLYndTbEhTNFlYaVNPKzc2dG8wbC9qc1ZyM0lqL25GUzBwdUtpZk1ZN3o3S3hKaXIvRlJ5VGxzM0NPZjJyaApnZ0ZiZDdobmZmNTVsSzJNNFAxTmY0KzJvVllrYWJ5UFlSR05EZ3NSL0RCSWRjTHl2d0kvdXNNMlc0eC9zRWtYCi92T1pQUFJ4Y1BYNjBxTWxOYXRnQVJsNjJhaHBsYlEwam4rS244THl3aVZXdm9LRE53eXFvOGRwWndRYmpzQkIKMU1nZk9lOWxKQnVNLytQZGtRWk8vOTg4MmUyYjgzVkwweXFyd044M0V1U2RkVDJYQXE5VWg1UU5zNFo0dmQxMwpITU5zMWYxVWFLdWZsYWUyUTMrZ1dwTEVoUklkKzdkSVFnaTNjSUxiZDZqWDdzZ1ZoM0Q5elVJdEdnPT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
kind: Secret
metadata:
  name: prometheus-ca
type: Opaque
```

### 2. OpenTelemetry Collector with Prometheus Remote Write Exporter
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel
spec:
  volumeMounts:
    - name: certs-volume
      mountPath: /certs
      readOnly: true
  volumes:
    - name: certs-volume
      secret:
        secretName: prometheus-ca
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.129.1
  mode: deployment
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
          http:
    processors:
    exporters:
      prometheusremotewrite:
        endpoint: "https://prometheus:9090/api/v1/write"
        tls:
          ca_file: /certs/ca.crt
        resource_to_telemetry_conversion:
          enabled: true
    service:
      pipelines:
        metrics:
          receivers: [otlp]
          exporters: [prometheusremotewrite]
```

### 3. Prometheus Deployment
The test deploys a Prometheus instance with remote write receiver enabled to receive metrics from the OpenTelemetry collector.

### 4. Metrics Generator
The test includes a metrics generator job that sends test metrics to the OpenTelemetry collector.

## 🚀 Test Steps

1. **Deploy Prometheus** - Create Prometheus deployment with remote write receiver enabled
2. **Create OTEL Collector** - Deploy collector with Prometheus remote write exporter
3. **Generate Metrics** - Send test metrics to the collector
4. **Verify Metrics** - Check that metrics are received and stored in Prometheus

## 🔍 Configuration Details

### TLS Configuration:
- **CA Certificate**: Custom CA certificate mounted from Kubernetes secret
- **Certificate File**: `/certs/ca.crt` mounted from secret volume
- **Endpoint**: `https://prometheus:9090/api/v1/write`
- **Verification**: TLS certificate validation enabled

### Conversion Settings:
- **Resource to Telemetry Conversion**: Enabled to include resource attributes as labels
- **Protocol**: Prometheus remote write protocol over HTTPS
- **Target**: Prometheus instance with remote write receiver

## 🧹 Cleanup

The test runs in the default namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Uses HTTPS endpoint with custom CA certificate for secure communication
- Mounts CA certificate from Kubernetes secret for TLS validation
- Enables resource to telemetry conversion for comprehensive labeling
- Demonstrates secure metric export to Prometheus with certificate-based authentication
- Tests complete pipeline from OTLP ingestion to Prometheus storage