#!/bin/bash

TOKEN=$(oc create token prometheus-user-workload -n openshift-user-workload-monitoring)
THANOS_QUERIER_HOST=$(oc get route thanos-querier -n openshift-monitoring -o json | jq -r '.spec.host')
# echo $TOKEN
# echo $THANOS_QUERIER_HOST

#Check metrics used in the prometheus rules created for TempoStack. Refer issue https://issues.redhat.com/browse/TRACING-3399 for skipped metrics.
# metrics="tempo_request_duration_seconds_count tempo_request_duration_seconds_sum tempo_request_duration_seconds_bucket tempo_build_info tempo_ingester_bytes_received_total tempo_ingester_flush_failed_retries_total tempo_ingester_failed_flushes_total tempo_ring_members"
metrics="tempo_ingester_traces_created_total tempo_distributor_spans_received_total tempo_discarded_spans_total"

for metric in $metrics; do
query="$metric"
count=0
    response=$(curl -s -k -H "Authorization: Bearer $TOKEN" -H "Content-type: application/json" "https://$THANOS_QUERIER_HOST/api/v1/query?query=$query")
    time=$(echo "$response" | jq -r '.data.result[0].value[0]')
    count=$(echo "$response" | jq -r '[.data.result[].value[1] | tonumber] | add')
    echo "$time;$count" >> $metric.log
    echo "Metric: $metric: $count"
done
