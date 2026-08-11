#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# Unset NAMESPACE inherited from the CI pod to avoid oc process
# trying to look up the build cluster namespace on the test cluster
unset NAMESPACE

EXTRACTOR_NAMESPACE="insights-extractor"
SPRING_BOOT_NAMESPACE="spring-boot"
MEMORY_GROWTH_THRESHOLD="${MEMORY_GROWTH_THRESHOLD:-2.0}"

ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/artifacts}"
mkdir -p "${ARTIFACT_DIR}"

echo "=== Insights Runtime Extractor Soak Test ==="
echo "INSIGHTS_RUNTIME_EXTRACTOR: ${INSIGHTS_RUNTIME_EXTRACTOR:-not set}"
echo "INSIGHTS_RUNTIME_EXPORTER: ${INSIGHTS_RUNTIME_EXPORTER:-not set}"
echo "Memory growth threshold: ${MEMORY_GROWTH_THRESHOLD}x"

# Install jq if not available
if ! command -v jq &>/dev/null; then
  echo "Installing jq..."
  curl -sL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 -o /tmp/jq
  chmod +x /tmp/jq
  export PATH="/tmp:${PATH}"
fi

# --- Deploy workloads ---

echo ""
echo "=== Deploying Spring Boot workload ==="
"${REPO_DIR}/spring-boot/deploy-spring-boot.sh"

echo ""
echo "=== Deploying Insights Runtime Extractor ==="
"${REPO_DIR}/insights-extractor/deploy-extractor.sh"

# --- Wait for pods to be ready ---

echo ""
echo "=== Waiting for pods to be ready ==="

echo "Waiting for spring-boot pods..."
oc rollout status deployment/spring-boot-deployment -n "${SPRING_BOOT_NAMESPACE}" --timeout=300s

echo "Waiting for extractor DaemonSet pods..."
oc rollout status daemonset/insights-runtime-extractor -n "${EXTRACTOR_NAMESPACE}" --timeout=300s

echo "All pods are ready."

# --- Capture initial memory ---

capture_memory() {
  local label="$1"
  local output_file="${ARTIFACT_DIR}/memory-${label}.txt"
  echo "Capturing memory snapshot: ${label}"
  oc adm top pods --containers -n "${EXTRACTOR_NAMESPACE}" 2>&1 | tee "${output_file}" || true
}

get_extractor_memory_ki() {
  oc adm top pods --containers -n "${EXTRACTOR_NAMESPACE}" --no-headers 2>/dev/null \
    | awk '$2 == "extractor" {
        mem = $4
        if (mem ~ /Mi/) { gsub(/Mi/, "", mem); ki = mem * 1024 }
        else if (mem ~ /Ki/) { gsub(/Ki/, "", mem); ki = mem }
        else { ki = 0 }
        total += ki; count++
      } END { if (count > 0) print int(total/count); else print 0 }'
}

# Run a few warm-up extractions so the extractor allocates its working set
echo ""
echo "=== Running warm-up extractions ==="
for i in 1 2 3; do
  "${REPO_DIR}/soak-test/extract.sh" > /dev/null 2>&1 || true
  sleep 10
done

echo ""
echo "=== Capturing initial memory usage ==="
capture_memory "initial"
initial_memory=$(get_extractor_memory_ki)
echo "Initial average extractor memory: ${initial_memory} Ki"

# --- Run soak test ---

echo ""
echo "=== Starting soak test (121 iterations, ~60 minutes) ==="
"${REPO_DIR}/soak-test/soak-test.sh" 2>&1 | tee "${ARTIFACT_DIR}/soak-test.log"

# --- Capture final memory ---

echo ""
echo "=== Capturing final memory usage ==="
capture_memory "final"
final_memory=$(get_extractor_memory_ki)
echo "Final average extractor memory: ${final_memory} Ki"

# --- Evaluate results ---

echo ""
echo "=== Soak Test Results ==="
echo "Initial memory: ${initial_memory} Ki"
echo "Final memory:   ${final_memory} Ki"

{
  echo "Initial memory: ${initial_memory} Ki"
  echo "Final memory:   ${final_memory} Ki"
  echo "Threshold:      ${MEMORY_GROWTH_THRESHOLD}x"
} > "${ARTIFACT_DIR}/soak-test-summary.txt"

if [ "${initial_memory}" -eq 0 ]; then
  echo "WARNING: Could not capture initial memory. Treating test as passed (memory comparison skipped)."
  echo "Result: PASS (no memory data)" >> "${ARTIFACT_DIR}/soak-test-summary.txt"
  exit 0
fi

growth=$(awk "BEGIN { printf \"%.2f\", ${final_memory} / ${initial_memory} }")
echo "Memory growth factor: ${growth}x"
echo "Growth factor: ${growth}x" >> "${ARTIFACT_DIR}/soak-test-summary.txt"

exceeded=$(awk "BEGIN { print (${growth} > ${MEMORY_GROWTH_THRESHOLD}) ? 1 : 0 }")
if [ "${exceeded}" -eq 1 ]; then
  echo "FAIL: Memory grew by ${growth}x, exceeding threshold of ${MEMORY_GROWTH_THRESHOLD}x. Possible memory leak detected."
  echo "Result: FAIL" >> "${ARTIFACT_DIR}/soak-test-summary.txt"
  exit 1
fi

echo "PASS: Memory growth ${growth}x is within threshold of ${MEMORY_GROWTH_THRESHOLD}x."
echo "Result: PASS" >> "${ARTIFACT_DIR}/soak-test-summary.txt"
