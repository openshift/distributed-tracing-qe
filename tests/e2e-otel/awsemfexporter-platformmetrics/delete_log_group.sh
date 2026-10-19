#!/bin/bash
# Stop the collectors of the test namespace, then delete the CloudWatch log group created by the AWS EMF
# exporter. A log group that does not exist is fine; any other error fails the cleanup so that it is noticed.
set -uo pipefail
region="us-east-2"
if [ -n "${CLUSTER_PROFILE_DIR:-}" ]; then
  export AWS_SHARED_CREDENTIALS_FILE="$CLUSTER_PROFILE_DIR/.awscred"
elif oc get secret aws-creds -n kube-system >/dev/null 2>&1; then
  access_key_id=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_access_key_id' | base64 -d) || access_key_id=""
  secret_access_key=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_secret_access_key' | base64 -d) || secret_access_key=""
  if [ -z "$access_key_id" ] || [ -z "$secret_access_key" ]; then
    echo "FAIL: could not read the aws-creds secret in kube-system"
    exit 1
  fi
  export AWS_ACCESS_KEY_ID="$access_key_id" AWS_SECRET_ACCESS_KEY="$secret_access_key"
fi
export AWS_PAGER=""
# stop the collectors first: this cleanup runs before chainsaw deletes the applied resources, and a collector
# that keeps exporting would recreate the log group or fail with ResourceNotFoundException
if [ -n "${NAMESPACE:-}" ]; then
  if ! oc delete opentelemetrycollector --all -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=90s >/dev/null 2>&1; then
    echo "FAIL: could not delete the collectors in $NAMESPACE; the log group is kept"
    exit 1
  fi
  remaining=unknown
  for i in $(seq 1 30); do
    # a failed pod query must not count as "no pods"
    if pods=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/managed-by=opentelemetry-operator --no-headers 2>/dev/null); then
      remaining=$(printf '%s' "$pods" | grep -c . || true)
      [ "$remaining" = "0" ] && break
    else
      remaining=unknown
    fi
    sleep 2
  done
  if [ "$remaining" != "0" ]; then
    echo "FAIL: collector pods still running (or the pod query failed: $remaining) in $NAMESPACE after 60 s; the log group is kept"
    exit 1
  fi
  echo "Collectors in $NAMESPACE stopped"
fi
if output=$(aws logs delete-log-group --log-group-name "$log_group_name" --region "$region" 2>&1); then
  echo "Log group $log_group_name deleted"
elif echo "$output" | grep -q 'ResourceNotFoundException'; then
  echo "Log group $log_group_name does not exist"
else
  echo "FAIL: could not delete log group $log_group_name: $output"
  exit 1
fi
