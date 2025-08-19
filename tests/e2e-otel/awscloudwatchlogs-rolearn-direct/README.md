# OpenTelemetry AWS CloudWatch Logs Exporter with Direct Role ARN Configuration Test

This test demonstrates AWS STS (Security Token Service) role assumption for the OpenTelemetry AWS CloudWatch Logs exporter using **direct `role_arn` parameter configuration** instead of service account annotations.

## 🎯 What This Test Does

This test validates and demonstrates:
- ✅ Direct `role_arn` parameter configuration in the exporter
- ✅ AWS Web Identity Token authentication flow without service account annotations
- ✅ OpenTelemetry Collector deployment with direct role specification
- ✅ Log delivery to AWS CloudWatch using direct role ARN configuration
- ✅ Simplified service account management without role annotations

## 🔐 Authentication Method: Direct Role ARN with Web Identity Token

This test uses the **AWS STS AssumeRoleWithWebIdentity** flow with direct role specification:

1. **No Service Account Annotation** - Service account has NO role ARN annotation
2. **Direct Role Configuration** - Role ARN specified directly in exporter configuration
3. **Web Identity Token** - Kubernetes provides JWT token at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
4. **Automatic Role Assumption** - AWS SDK automatically exchanges token for temporary credentials using direct role ARN
5. **CloudWatch Access** - Temporary credentials used to write logs to CloudWatch

## 🔄 Key Differences from Standard STS Configuration

### Service Account Configuration
- **Standard STS**: Service account has `eks.amazonaws.com/role-arn` annotation
- **This Test**: Service account has **NO** role ARN annotation

### Role ARN Specification
- **Standard STS**: Role ARN specified via service account annotation or environment variable
- **This Test**: Role ARN specified directly in the exporter configuration using `role_arn` parameter

### Exporter Configuration
```yaml
exporters:
  awscloudwatchlogs:
    log_group_name: "${env:LOG_GROUP_NAME}"
    region: "${env:AWS_REGION}"
    role_arn: "${env:ROLE_ARN}"  # ← Direct role ARN configuration
    # ... other configuration
```

## 📋 Test Resources

### Key Files in This Directory

1. **[`chainsaw-test.yaml`](./chainsaw-test.yaml)** - Chainsaw test orchestration (namespace: `chainsaw-awssts-cloudwatch-direct`)
2. **[`otel-collector-rolearn.yaml`](./otel-collector-rolearn.yaml)** - Collector with direct role_arn configuration
3. **[`create-aws-rolearn-secret.sh`](./create-aws-rolearn-secret.sh)** - AWS IAM role and secret creation
4. **[`check_logs_rolearn.sh`](./check_logs_rolearn.sh)** - Main verification script for direct role_arn
5. **[`check_role_arn_config.sh`](./check_role_arn_config.sh)** - Direct role_arn configuration validation
6. **[`aws-sts-cloudwatch-delete.sh`](./aws-sts-cloudwatch-delete.sh)** - AWS resource cleanup
7. **[`app-plaintext-logs.yaml`](./app-plaintext-logs.yaml)** - Log generator application

## 🚀 How to Run This Test

```bash
# Set kubeconfig (required for OpenShift/Kubernetes cluster access)
export KUBECONFIG=~/path/to/kubeconfig

# Run the direct role ARN test
chainsaw test --test-dir tests/e2e-otel/awscloudwatchlogs-rolearn-direct/

# Run with specific namespace (optional)
chainsaw test --test-dir tests/e2e-otel/awscloudwatchlogs-rolearn-direct/ --namespace my-test-ns
```

## 🔧 Test Configuration

### Service Account WITHOUT STS Annotation
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otelcol-cloudwatch
  namespace: chainsaw-awssts-cloudwatch-direct
  # NO eks.amazonaws.com/role-arn annotation!
```

### Environment Variables for Direct Role ARN
```yaml
env:
  - name: AWS_REGION
    valueFrom:
      secretKeyRef:
        name: aws-sts-cloudwatch
        key: region
  - name: ROLE_ARN  # ← Direct role ARN environment variable
    valueFrom:
      secretKeyRef:
        name: aws-sts-cloudwatch
        key: role_arn
  - name: AWS_WEB_IDENTITY_TOKEN_FILE
    value: /var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

### CloudWatch Logs Exporter with Direct Role ARN
```yaml
exporters:
  awscloudwatchlogs:
    log_group_name: "${env:LOG_GROUP_NAME}"
    log_stream_name: "tracing-otelcol-stream"
    raw_log: true
    region: "${env:AWS_REGION}"
    role_arn: "${env:ROLE_ARN}"  # ← Direct role ARN configuration
    endpoint: "https://logs.us-east-2.amazonaws.com"
    log_retention: 1
    tags: { 'tracing-otel': 'true', 'test-type': 'aws-sts-direct' }
```

## 🔍 What the Test Validates

### 1. AWS IAM Setup
- ✅ CloudWatch log group creation
- ✅ IAM role creation with proper trust policy
- ✅ IAM policy attachment for CloudWatch Logs access
- ✅ Kubernetes secret creation with role ARN

### 2. Direct Role ARN Configuration
- ✅ Service account created WITHOUT role ARN annotation
- ✅ Environment variable for direct role ARN
- ✅ Web identity token file mount
- ✅ Collector deployment with direct role specification

### 3. Authentication Flow
- ✅ AWS SDK automatic role assumption using direct role_arn
- ✅ Temporary credential generation
- ✅ CloudWatch API access with assumed role
- ✅ Log delivery to CloudWatch

### 4. End-to-End Verification
- ✅ OpenTelemetry Collector pod startup
- ✅ Log export to AWS CloudWatch using direct role_arn
- ✅ CloudWatch log group and stream validation
- ✅ Log content verification

## 📊 Expected Test Results

```bash
=== AWS CloudWatch Logs Direct Role ARN Test Verification ===
Log Group: tracing-chainsaw-awssts-cloudwatch-direct-ciotelcwl
Region: us-east-2
Role ARN: arn:aws:iam::301721915996:role/tracing-cloudwatch-chainsaw-awssts-cloudwatch-direct-ciotelcwl

✓ Collector pod is running successfully
✓ Service account correctly has no STS annotation (using direct role_arn)
✓ Role ARN configuration found in logs
✓ No AWS-related errors found in collector logs
✓ Log group found in CloudWatch
✓ Log streams found in CloudWatch
✓ Log events found in CloudWatch

=== Test Verification Complete ===
This test successfully demonstrates:
✓ Direct role_arn configuration in exporter
✓ Collector startup with role ARN parameter
✓ CloudWatch Logs exporter using direct role_arn configuration

Direct role_arn configuration enables secure, temporary access to AWS services
by specifying the role directly in the exporter configuration.
```

## 🔄 Direct Role ARN Authentication Flow

```
1. Kubernetes Service Account (NO annotation)
   ↓ (no role ARN annotation needed)
2. Direct Role ARN Configuration
   ↓ (specified in exporter config)
3. Web Identity Token (JWT)
   ↓ (mounted at token file path)
4. AWS SDK STS AssumeRoleWithWebIdentity
   ↓ (using direct role_arn parameter)
5. Temporary AWS Credentials
   ↓ (access key, secret key, session token)
6. CloudWatch Logs API Access
   ↓ (using temporary credentials)
7. Log Delivery to CloudWatch
```

## 🛡️ Security Benefits of Direct Role ARN

1. **Explicit Role Specification** - Role is clearly visible in exporter configuration
2. **No Service Account Dependency** - Reduced coupling with service account annotations
3. **Per-Exporter Configuration** - Different exporters can use different roles
4. **Clear Audit Trail** - Role usage is explicit in configuration
5. **Simplified Service Account Management** - No need to manage role annotations

## 💡 Advantages of Direct Role ARN Configuration

### Configuration Clarity
- Role ARN is explicitly visible in the exporter configuration
- No need to check service account annotations to understand which role is used
- Easier to audit and review IAM role usage

### Flexibility
- Different exporters in the same collector can use different roles
- Role can be easily changed without modifying service account
- Supports dynamic role configuration through environment variables

### Simplified Management
- Service accounts don't need role annotations
- Reduced dependency on Kubernetes-specific AWS integrations
- Works consistently across different Kubernetes distributions

## 🔧 Prerequisites

### AWS Environment
- AWS account with IAM permissions
- CloudWatch Logs service access
- STS (Security Token Service) enabled

### Kubernetes/OpenShift Cluster
- Service account token projection support
- Network access to AWS APIs
- Proper RBAC for OpenTelemetry Operator

### Test Environment Variables
- `OPENSHIFT_BUILD_NAMESPACE` - Used for resource naming
- `KUBECONFIG` - Kubernetes cluster access

## 🧹 Cleanup

The test automatically cleans up AWS resources in the cleanup phase:

```bash
# Manual cleanup if needed
./aws-sts-cloudwatch-delete.sh otelcol-cloudwatch chainsaw-awssts-cloudwatch-direct
```

This removes:
- IAM role and policy
- CloudWatch log group
- Kubernetes secret

## 🐛 Troubleshooting

### Common Issues

1. **Pod Not Found Error**
   - Check pod label selector in verification scripts
   - Ensure correct namespace is used (`chainsaw-awssts-cloudwatch-direct`)

2. **Role ARN Not Found**
   - Verify the role_arn parameter is correctly set in exporter configuration
   - Check environment variable `ROLE_ARN` is properly configured

3. **STS Permission Denied**
   - Verify IAM role trust policy allows web identity
   - Check that role ARN is correctly specified in exporter

4. **CloudWatch Access Denied**
   - Verify IAM policy includes CloudWatch Logs permissions
   - Check log group name and region configuration

### Debug Commands

```bash
# Check collector pod status
oc get pods -n chainsaw-awssts-cloudwatch-direct -l app.kubernetes.io/name=otelcol-cloudwatch-collector

# View collector logs
oc logs -n chainsaw-awssts-cloudwatch-direct deployment/otelcol-cloudwatch-collector

# Check service account (should have NO role annotation)
oc get serviceaccount otelcol-cloudwatch -n chainsaw-awssts-cloudwatch-direct -o yaml

# Verify secret contents
oc get secret aws-sts-cloudwatch -n chainsaw-awssts-cloudwatch-direct -o yaml

# Check collector configuration for role_arn
oc get opentelemetrycollector otelcol-cloudwatch -n chainsaw-awssts-cloudwatch-direct -o yaml
```

## 🔗 Related Documentation

- [AWS CloudWatch Logs Exporter Role ARN Configuration](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/awscloudwatchlogsexporter)
- [AWS STS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [OpenTelemetry AWS CloudWatch Logs Exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/awscloudwatchlogsexporter)

## 🏷️ Test Categories

- **Component**: AWS CloudWatch Logs Exporter  
- **Feature**: Direct Role ARN Configuration
- **Status**: ✅ Fully Implemented and Working
- **Environment**: OpenShift/Kubernetes + AWS
- **Authentication**: AWS STS Web Identity Token with Direct Role ARN
- **Namespace**: `chainsaw-awssts-cloudwatch-direct`