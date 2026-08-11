#!/bin/bash
set -euo pipefail

NAMESPACE="insights-extractor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pods=$(oc get pods -n "${NAMESPACE}" --selector=app.kubernetes.io/name=insights-runtime-extractor --no-headers -o custom-columns=":metadata.name")

rm -f "${SCRIPT_DIR}/out.json"
for pod in $pods; do
  echo "Extracting runtime info from ${pod}..."
  oc exec -n "${NAMESPACE}" "${pod}" -c exporter -- curl -s http://127.0.0.1:8000/gather_runtime_info?hash=false >> "${SCRIPT_DIR}/out.json"
done

jq -s 'add' "${SCRIPT_DIR}/out.json"
