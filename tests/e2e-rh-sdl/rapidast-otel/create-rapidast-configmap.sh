#!/bin/bash

otel_token=$(oc create token privileged-sa -n rapidast-otel)

# RapiDAST scans one OpenAPI document per run. The OpenTelemetry operator API is split in two versions of the
# opentelemetry.io group: v1alpha1 (Instrumentation, OpAMPBridge, TargetAllocator) and v1beta1 (OpenTelemetryCollector,
# which is no longer served as v1alpha1). Generate one RapiDAST config for each, the job runs them one after the other.
rapidast_config() {
  local short_name=$1 api_version=$2
  cat <<EOF
config:
  configVersion: 6
  googleCloudStorage:
    keyFile: "/etc/gcs/sa-key"
    bucketName: "secaut-bucket"
    directory: "rhosdt/${RHOSDT_VERSION}/otel"
  results:
    exclusions:
      enabled: True
      rules:
        - name: "Filter unauthorized responses on operator APIs"
          description: "Exclude 401 unauthorized responses which are expected for operator API endpoints"
          cel_expression: '.result.webResponse.statusCode == 401'
        - name: "Filter forbidden responses on operator APIs"
          description: "Exclude 403 forbidden responses which are expected for operator API endpoints"
          cel_expression: '.result.webResponse.statusCode == 403'
        - name: "Filter operator API discovery false positives"
          description: "Exclude common false positives from operator API discovery scans"
          cel_expression: '.result.ruleId in ["10015", "10027", "10096", "10024", "10054"]'

application:
  shortName: "${short_name}"
  url: "https://kubernetes.default.svc"

general:
  authentication:
    type: "http_header"
    parameters:
      name: "Authorization"
      value: "Bearer ${otel_token}"
  container:
    type: "none"

scanners:
  zap:
    apiScan:
      apis:
        apiUrl: "https://kubernetes.default.svc/openapi/v3/apis/opentelemetry.io/${api_version}"
    passiveScan:
      disabledRules: "2"
    activeScan:
      policy: "Operator-scan"
    miscOptions:
      enableUI: False
      updateAddons: True
      memMaxHeap: "2048m"
      additionalAddons: "openapi,authentication"
EOF
}

# Define the content for the ConfigMap, with one config file per API version
configmap_content=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: rapidast-configmap
  namespace: rapidast-otel
data:
  rapidastconfig-v1alpha1.yaml: |
$(rapidast_config "otel" "v1alpha1" | sed 's/^/    /')
  rapidastconfig-v1beta1.yaml: |
$(rapidast_config "otel-v1beta1" "v1beta1" | sed 's/^/    /')
EOF
)

# Create the ConfigMap
echo "$configmap_content" | oc -n rapidast-otel create -f -
