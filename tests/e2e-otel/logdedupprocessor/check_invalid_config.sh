#!/bin/bash
# This script checks that a collector whose log_dedup processor sets both include_fields and
# exclude_fields refuses to start and reports the reason.

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector,app.kubernetes.io/instance=${NAMESPACE}.logdedup-invalid"
EXPECTED_ERROR="cannot define both exclude_fields and include_fields"

for attempt in $(seq 1 24); do
  POD=$(kubectl -n "$NAMESPACE" get pods -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD" ]; then
    READY=$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    if [ "$READY" = "true" ]; then
      echo "The collector with an invalid log_dedup configuration is ready, but it must not start."
      exit 1
    fi
    if kubectl -n "$NAMESPACE" logs "$POD" 2>/dev/null | grep -q -- "$EXPECTED_ERROR"; then
      echo "The collector rejected the configuration: \"$EXPECTED_ERROR\""
      exit 0
    fi
  fi
  echo "Attempt $attempt: waiting for the collector to report the configuration error, retrying in 5s..."
  sleep 5
done

echo "Timed out waiting for the configuration error \"$EXPECTED_ERROR\"."
exit 1
