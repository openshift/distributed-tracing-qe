#!/bin/bash
# The scheduler and the controller manager run in the cluster only when the control plane is not hosted
# (infrastructure.status.controlPlaneTopology is HighlyAvailable or SingleReplica). The check Job reads
# the topology from this config map and skips the control plane expectations on hosted control planes.
set -euo pipefail
topology=$(oc get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}')
echo "controlPlaneTopology: ${topology:-unknown}"
oc create configmap check-config -n "$NAMESPACE" --from-literal=control_plane_topology="${topology:-unknown}" --dry-run=client -o yaml | oc apply -f -
