#!/bin/bash
# This script verifies the k8s_leader_elector extension is working correctly:
# 1. A Lease object exists in the test namespace
# 2. Leader election log messages are present in collector pods
# 3. Metrics are collected by the leader pod

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=chainsaw-k8sleaderelectorext
LEASE_NAME="otel-k8sclusterreceiver-leader"

FOUND_LEASE=false
FOUND_METRICS=false
FOUND_LEADER_LOG=false

while ! $FOUND_LEASE || ! $FOUND_METRICS || ! $FOUND_LEADER_LOG; do
    # Check that the Lease object exists
    if ! $FOUND_LEASE && kubectl -n $NAMESPACE get lease $LEASE_NAME > /dev/null 2>&1; then
        HOLDER=$(kubectl -n $NAMESPACE get lease $LEASE_NAME -o jsonpath='{.spec.holderIdentity}')
        echo "Lease '$LEASE_NAME' found with holder: $HOLDER"
        FOUND_LEASE=true
    fi

    PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

    for POD in "${PODS[@]}"; do
        LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=500 2>/dev/null)

        # Check for leader election activity (klog uses capital "Successfully acquired lease")
        if ! $FOUND_LEADER_LOG && echo "$LOGS" | grep -qi -e "successfully acquired lease" -e "Starting k8sClusterReceiver with leader election"; then
            echo "Leader election log found in $POD"
            FOUND_LEADER_LOG=true
        fi

        # Check for k8s cluster metrics (only the leader should produce these)
        if ! $FOUND_METRICS && echo "$LOGS" | grep -q "k8s.node.allocatable_cpu"; then
            echo "Metrics 'k8s.node.allocatable_cpu' found in $POD"
            FOUND_METRICS=true
        fi
    done

    sleep 5
done

echo ""
echo "=== Leader Election Extension Verification ==="
echo "Lease object created: PASS"
echo "Leader election active: PASS"
echo "Metrics collected by leader: PASS"
echo "All checks passed."
