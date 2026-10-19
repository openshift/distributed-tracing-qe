# OpenShift platform metrics with the collector only (no monitoring stack)

Collects the OpenShift platform metrics with the OpenTelemetry collector and operator alone and verifies them
on the collector's Prometheus exporter. Nothing in the `openshift-monitoring` namespace is read or modified, so
the test also passes on clusters without the monitoring stack. It has no OpenShift version requirement.

```
node collector (DaemonSet, every node)                cluster collector (Deployment)
  host_metrics   root_path /hostfs (read-only)          k8s_cluster  distribution: openshift
  kubelet_stats  auth_type kubeConfig                   prometheus   kube-apiserver (kube root CA),
                 -> API server node proxy                            kube-scheduler, kube-controller-manager,
  resource_detection (openshift, k8s_api)                            ovn-kubernetes-node, machine-config-daemon,
                       --OTLP-->                                      router-default (service CA, SA token)
                                                        prometheus exporter :8889  <-- check Job
```

## Resources

| File | Purpose |
|---|---|
| `rbac-scc.yaml` | Service accounts, the unprivileged `SecurityContextConstraints` of the node collector (hostPath read-only, root with `spc_t`, no privileged container), the `ClusterRole`s (`nodes/proxy` for the kubelet through the API server proxy; `/metrics`, `/metrics/resources`, `namespace/metrics`, `routers/metrics` for the platform endpoints; the `k8s_cluster` list/watch rules) and the service CA config map |
| `cluster-collector.yaml` | `k8s_cluster` receiver, `prometheus` receiver with the three scrape patterns of the documentation (kube-apiserver through `default/kubernetes`; scheduler and controller manager with the service CA; kube-rbac-proxy DaemonSets), OTLP receiver for the node collectors, Prometheus exporter for the check |
| `node-collector.yaml` | `host_metrics` and `kubelet_stats` receivers, `resource_detection`, OTLP export to the cluster collector |
| `record_control_plane_topology.sh` | Stores `infrastructure.status.controlPlaneTopology` in a config map: on hosted control planes (`External`) the scheduler, controller manager and machine-config daemon are not in the cluster and the Job does not expect their metrics |
| `check-metrics.yaml` | Job that fetches the Prometheus exporter and expects the node (`system_*`), kubelet (`k8s_node_*`, `k8s_pod_*`, `container_*`), cluster state (`k8s_pod_phase`, `k8s_deployment_available`, `k8s_node_condition_ready`) and control plane metrics with their resource attributes as labels, and no scrape target down |

## Notes

* Component identifiers: `host_metrics`, `kubelet_stats` and `resource_detection` are the canonical names in collector 0.158; `hostmetrics`, `kubeletstats` and `resourcedetection` are deprecated aliases.
* The kubelet CA (`kubelet-serving-ca` config map) is namespaced and rotates; reaching the kubelet through the API server node proxy avoids both a CA copy and `insecure_skip_verify`.
* Not reachable with a service account token on OpenShift 5.0 and therefore not part of the test: etcd (client certificate), cluster-version-operator, node-tuning-operator, cluster-samples-operator, marketplace-operator, the CSI controller kube-rbac-proxy (client certificate only), and dns-default, dns-operator, ingress-operator (NetworkPolicy admits only the `openshift-monitoring` namespace).
* On hosted control planes (`controlPlaneTopology: External`, for example the Konflux integration test clusters) the Job skips the scheduler, controller manager and machine-config daemon expectations; the kube-apiserver job then reaches the hosted API server through `default/kubernetes`, a path that has been verified on standalone clusters only.
* Related: TRACING-6911, TRACING-6910 (PoC, github.com/IshwarKanse/demo `otel-ocp-metrics-export/collector-only`), TRACING-4524.
