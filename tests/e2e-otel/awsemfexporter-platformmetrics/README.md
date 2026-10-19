# OpenShift platform metrics without the monitoring stack, exported to AWS CloudWatch

The same two collectors as [`platformmetrics-collector-only`](../platformmetrics-collector-only/) (node
DaemonSet with `host_metrics` and `kubelet_stats`, cluster Deployment with `k8s_cluster` and the `prometheus`
receiver scraping the control plane with the service account token), with the AWS EMF exporter towards
CloudWatch instead of the Prometheus exporter. Nothing in `openshift-monitoring` is read or modified.

The check queries the CloudWatch API for data points of this run (`system.cpu.time` and `k8s.node.cpu.time` for
a worker node, `k8s.pod.cpu.time` and `k8s.pod.phase` of the test namespace, `apiserver_request_total` of the
`kube-apiserver` job) and for the EMF log stream; the log group is deleted when the test ends.

AWS credentials come from `CLUSTER_PROFILE_DIR/.awscred` (OpenShift CI), the `aws-creds` secret in
`kube-system` (AWS IPI cluster) or the AWS CLI configuration. The directory name matches the `*aws*` pattern
that the Konflux integration tests skip (no credentials there).

Related: TRACING-6911, TRACING-6910, TRACING-4524.
