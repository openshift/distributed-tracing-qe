#!/bin/bash

tempo_token=$(oc create token privileged-sa -n rapidast-tempo)

# Define the content for the ConfigMap
configmap_content=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: rapidast-configmap
  namespace: rapidast-tempo
data:
  rapidastconfig.yaml: |
    config:
      configVersion: 6
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
      shortName: "tempo"
      url: "https://kubernetes.default.svc"

    general:
      authentication:
        type: "http_header"
        parameters:
          name: "Authorization"
          value: "Bearer ${tempo_token}"
      container:
        type: "none"

    scanners:
      zap:
        apiScan:
          apis:
            apiUrl: "https://kubernetes.default.svc/openapi/v3/apis/tempo.grafana.com/v1alpha1"
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
)

# Create the ConfigMap
echo "$configmap_content" | oc -n rapidast-tempo create -f -

