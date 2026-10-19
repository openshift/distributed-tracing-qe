#!/bin/bash
# Verify in CloudWatch that the node metrics (host_metrics), the pod metrics (kubelet_stats), the cluster
# state (k8s_cluster) and the control plane metrics (prometheus receiver) collected without the monitoring
# stack arrived through the AWS EMF exporter during this test run. Nothing in openshift-monitoring is used.
set -uo pipefail
region="us-east-2"
cw_namespace="Tracing-OCP-Platform"

# Fetch AWS credentials based on CLUSTER_PROFILE_DIR variable
if [ -n "${CLUSTER_PROFILE_DIR:-}" ]; then
    AWS_ACCESS_KEY_ID=$(sed -n 's/^[[:space:]]*aws_access_key_id[[:space:]]*=[[:space:]]*//p' "${CLUSTER_PROFILE_DIR}/.awscred" | head -n1 | sed 's/[[:space:]]*$//')
    AWS_SECRET_ACCESS_KEY=$(sed -n 's/^[[:space:]]*aws_secret_access_key[[:space:]]*=[[:space:]]*//p' "${CLUSTER_PROFILE_DIR}/.awscred" | head -n1 | sed 's/[[:space:]]*$//')
elif oc get secret aws-creds -n kube-system >/dev/null 2>&1; then
    AWS_ACCESS_KEY_ID=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_access_key_id' | base64 -d)
    AWS_SECRET_ACCESS_KEY=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_secret_access_key' | base64 -d)
elif aws sts get-caller-identity >/dev/null 2>&1; then
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
else
    echo "No AWS credentials found (CLUSTER_PROFILE_DIR, aws-creds secret in kube-system, or AWS CLI configuration)"
    exit 1
fi
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "FAIL: the AWS credentials are empty"
    exit 1
fi
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=${region}
export AWS_PAGER=""
# from here on a failing aws or oc command fails the test instead of producing a misleading message
set -e

# Only data points published since this test run started count: list-metrics would also return metrics
# that an earlier run published up to two weeks ago. The run start is the creation time of the node
# collector. The metrics searched are the OTelLib + <dimension> rollups that the EMF exporter creates with
# ZeroAndSingleDimensionRollup; the dimensions come from the resource attributes (the prometheus receiver stores the
# scrape job as service.name).
run_start=$(oc get daemonset node-collector -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}')
if [ -z "$run_start" ]; then
  echo "FAIL: could not determine the start of the test run"
  exit 1
fi
node=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
# the resource_detection processor adds k8s.cluster.name (the infrastructure name) to every series; the metrics
# of this cluster must exist under that dimension too, so that a parallel run of another cluster in the same
# AWS account cannot satisfy the check. The EMF exporter creates one rollup per single dimension
# (ZeroAndSingleDimensionRollup), so the cluster and the other dimension are checked as two single-dimension
# searches, not as a pair.
cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
if [ -z "$cluster_name" ]; then
  echo "FAIL: could not determine the OpenShift infrastructure name"
  exit 1
fi
found_metric() { # metric name, dimension name, dimension value
  local search count
  search="SEARCH('{${cw_namespace},OTelLib,$2} MetricName=\"$1\" \"$2\"=\"$3\"', 'SampleCount', 60)"
  count=$(aws cloudwatch get-metric-data --region "$region" --start-time "$run_start" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --metric-data-queries "[{\"Id\":\"q\",\"Expression\":$(printf '%s' "$search" | jq -R .),\"Period\":60}]" \
    --query 'sum(MetricDataResults[].length(Values))' --output text 2>/dev/null) || return 1
  [ -n "$count" ] && [ "$count" != "None" ] && [ "$count" -gt 0 ] 2>/dev/null
}
all_found() {
  found_metric system.cpu.time k8s.node.name "$node" \
    && found_metric k8s.node.cpu.time k8s.node.name "$node" \
    && found_metric k8s.pod.cpu.time k8s.namespace.name "$NAMESPACE" \
    && found_metric k8s.pod.phase k8s.namespace.name "$NAMESPACE" \
    && found_metric apiserver_request_total service.name kube-apiserver \
    && found_metric system.cpu.time k8s.cluster.name "$cluster_name" \
    && found_metric k8s.pod.phase k8s.cluster.name "$cluster_name" \
    && found_metric apiserver_request_total k8s.cluster.name "$cluster_name"
}

# CloudWatch lists new metrics with a delay; stop well before the 15 minute step timeout
deadline=$(( $(date +%s) + 600 ))
attempt=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  attempt=$((attempt + 1))
  echo "Attempt $attempt: looking for data points published since $run_start in the CloudWatch namespace $cw_namespace"
  if all_found; then
    echo "Node (system.cpu.time), kubelet (k8s.node.cpu.time, k8s.pod.cpu.time), cluster state (k8s.pod.phase) and control plane (apiserver_request_total) metrics of cluster $cluster_name are in CloudWatch."
    break
  fi
  sleep 10
done
if ! all_found; then
  echo "FAIL: expected metrics with data points from this run not found in CloudWatch namespace $cw_namespace"
  exit 1
fi

# The EMF log stream carries the raw records
STREAMS=$(aws logs describe-log-streams --log-group-name "$log_group_name" --log-stream-name-prefix "$log_stream_name" --region "$region" --query 'logStreams[].logStreamName' --output text)
if [[ "$STREAMS" == *"$log_stream_name"* ]]; then
  echo "EMF log stream $log_stream_name exists in log group $log_group_name"
else
  echo "FAIL: EMF log stream $log_stream_name not found in log group $log_group_name"
  exit 1
fi
echo "OpenShift platform metrics were collected without the monitoring stack and exported to AWS CloudWatch via the AWS EMF exporter."
