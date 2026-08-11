#!/bin/bash
set -euo pipefail

NAMESPACE="insights-extractor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Deploying Insights Runtime Extractor to namespace ${NAMESPACE}..."

# Create namespace (idempotent)
oc create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

# Add Pod Security Admission labels for privileged workloads (OCP 4.22+)
oc label namespace "${NAMESPACE}" \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite

# Apply SCC and RBAC resources
oc apply -n "${NAMESPACE}" -f "${SCRIPT_DIR}/insights-runtime-extractor-scc.yaml"

# Process template with CI-provided images and deploy
oc process --local -f "${SCRIPT_DIR}/insights-runtime-extractor.yaml" \
    -p EXPORTER_IMAGE="${INSIGHTS_RUNTIME_EXPORTER}" \
    -p EXTRACTOR_IMAGE="${INSIGHTS_RUNTIME_EXTRACTOR}" | oc apply -n "${NAMESPACE}" -f -

echo "Extractor deployment applied in namespace ${NAMESPACE}."
