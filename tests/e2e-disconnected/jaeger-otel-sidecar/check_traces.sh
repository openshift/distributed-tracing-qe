#!/bin/bash
JAEGER_URL=$(oc -n kuttl-jaeger-otel-sidecar get route jaeger-production -o json | jq '.spec.host' -r)
SERVICE_NAME="order"

while true; do
  trace_exists=$(curl -ksSL "https://$JAEGER_URL/api/traces?service=$SERVICE_NAME&limit=1" | jq -r '.data | length')

  if [[ $trace_exists -gt 0 ]]; then
    echo "Traces for $SERVICE_NAME exist in Jaeger."
    break
  else
    echo "Trace for $SERVICE_NAME does not exist in Jaeger. Retrying..."
    sleep 5  # Wait for 5 seconds before retrying
  fi
done
