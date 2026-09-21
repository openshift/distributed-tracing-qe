#!/bin/bash
# This script checks the debug exporter output of the OpenTelemetry collector for the
# deduplicated logs of the log_dedup processor.
#
# Two tenants (x-scope-orgid header, configured in metadata_keys) each send the same log 5 times.
# The processor has to keep the tenants apart, so the log_count values of the deduplicated
# records add up to 10 and no single record counts more than 5. Logs that do not match the
# processor condition must pass through unchanged, without a log_count attribute.

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector,app.kubernetes.io/instance=${NAMESPACE}.logdedup"
EXPECTED_SUM=10
MAX_PER_TENANT=5
EXPECTED_PASSTHROUGH=3

for attempt in $(seq 1 24); do
  POD=$(kubectl -n "$NAMESPACE" get pods -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$POD" ]; then
    echo "Attempt $attempt: no collector pod found yet, retrying in 5s..."
    sleep 5
    continue
  fi

  LOGS=$(kubectl -n "$NAMESPACE" logs "$POD" --tail=-1)

  sum=0
  max=0
  records=0
  passthrough=0
  passthrough_with_count=0
  kind=""
  while IFS= read -r line; do
    case "$line" in
      *"LogRecord #"*) kind="" ;;
      *"Body: Str(duplicate message)"*) kind="dedup" ;;
      *"Body: Str(unique passthrough message)"*)
        kind="passthrough"
        passthrough=$((passthrough + 1))
        ;;
      *"-> log_count: Int("*)
        n=${line##*Int(}
        n=${n%%)*}
        if [ "$kind" = "dedup" ]; then
          sum=$((sum + n))
          records=$((records + 1))
          if [ "$n" -gt "$max" ]; then max=$n; fi
        elif [ "$kind" = "passthrough" ]; then
          passthrough_with_count=$((passthrough_with_count + 1))
        fi
        ;;
    esac
  done <<< "$LOGS"

  echo "Attempt $attempt: deduplicated records=$records sum(log_count)=$sum max(log_count)=$max passthrough=$passthrough passthrough_with_log_count=$passthrough_with_count"

  if [ "$sum" -eq "$EXPECTED_SUM" ] && [ "$records" -ge 2 ] && [ "$max" -le "$MAX_PER_TENANT" ] \
     && [ "$passthrough" -eq "$EXPECTED_PASSTHROUGH" ] && [ "$passthrough_with_count" -eq 0 ]; then
    if ! echo "$LOGS" | grep -q -- "-> first_observed_timestamp: Str("; then
      echo "first_observed_timestamp attribute not found on the deduplicated logs"
      exit 1
    fi
    if ! echo "$LOGS" | grep -q -- "-> last_observed_timestamp: Str("; then
      echo "last_observed_timestamp attribute not found on the deduplicated logs"
      exit 1
    fi
    echo "Logs of both tenants were deduplicated separately and non-matching logs passed through unchanged."
    exit 0
  fi

  # More than expected can never become correct by waiting.
  if [ "$sum" -gt "$EXPECTED_SUM" ] || [ "$max" -gt "$MAX_PER_TENANT" ] || [ "$passthrough_with_count" -gt 0 ]; then
    echo "Unexpected deduplication result (tenants merged or passthrough logs deduplicated)."
    exit 1
  fi

  sleep 5
done

echo "Timed out waiting for the deduplicated logs."
exit 1
