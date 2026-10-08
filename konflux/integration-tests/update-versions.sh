#!/bin/bash
set -euo pipefail

# Sets the per-release defaults of the integration test pipelines in this directory.
#
# Usage: konflux/integration-tests/update-versions.sh <rhosdt-version> <art-version> [fbc-ocp-version]
#   rhosdt-version   product version, the tests branch is rhosdt-<rhosdt-version> (for example 3.11)
#   art-version      ART group version of the FBC tags, rhosdt-<art-version>__v<ocp>__... (for example 0.158)
#   fbc-ocp-version  OCP version of the FBC used to read the name of the newest CSV (default 4.22)
#
# The operator, collector and target allocator versions come from the product branch of
# openshift/open-telemetry-opentelemetry-operator and os-observability/redhat-opentelemetry-collector,
# the name of the CSV from the stable channel of the ART catalog.
# Needs: curl, jq, yq, oc and opm.

RHOSDT_VERSION=${1:?Usage: $0 <rhosdt-version> <art-version> [fbc-ocp-version]}
ART_VERSION=${2:?Usage: $0 <rhosdt-version> <art-version> [fbc-ocp-version]}
FBC_OCP_VERSION=${3:-4.22}

DIR=$(cd "$(dirname "$0")" && pwd)
TESTS_BRANCH="rhosdt-${RHOSDT_VERSION}"
OPERATOR_REPO=https://raw.githubusercontent.com/openshift/open-telemetry-opentelemetry-operator
COLLECTOR_REPO=https://raw.githubusercontent.com/os-observability/redhat-opentelemetry-collector

echo "Reading the versions of the ${TESTS_BRANCH} branch..."
VERSIONS_TXT=$(curl -fsSL "${OPERATOR_REPO}/${TESTS_BRANCH}/versions.txt")
OPERATOR_VERSION=$(awk -F= '/^opentelemetry-collector=/ {print $2}' <<<"${VERSIONS_TXT}")
TARGETALLOCATOR_VERSION=$(awk -F= '/^targetallocator=/ {print $2}' <<<"${VERSIONS_TXT}")
COLLECTOR_VERSION=$(curl -fsSL "${COLLECTOR_REPO}/${TESTS_BRANCH}/manifest.yaml" | yq '.dist.version')
for var in OPERATOR_VERSION TARGETALLOCATOR_VERSION COLLECTOR_VERSION; do
  if [[ -z "${!var}" || "${!var}" == "null" ]]; then
    echo "Could not read ${var} from the ${TESTS_BRANCH} branch" >&2
    exit 1
  fi
done

echo "Reading the CSV of the head of the stable channel in the FBC of OCP ${FBC_OCP_VERSION}..."
FBC="quay.io/redhat-user-workloads/ocp-art-tenant/art-fbc:rhosdt-${ART_VERSION}__v${FBC_OCP_VERSION}__opentelemetry-rhel9-operator"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
oc image extract "${FBC}" --filter-by-os=linux/amd64 --path /configs/:"${WORK}" --confirm
CSV_NAME=$(opm render "${WORK}/opentelemetry-product" -o json \
  | jq -r 'select(.schema == "olm.channel" and .name == "stable") | .entries[].name' | sort -V | tail -n1)
[ -n "${CSV_NAME}" ] || { echo "No CSV found in the stable channel of ${FBC}" >&2; exit 1; }

echo
echo "Tests branch:        ${TESTS_BRANCH}"
echo "Operator:            ${OPERATOR_VERSION}"
echo "Collector:           ${COLLECTOR_VERSION}"
echo "Target allocator:    ${TARGETALLOCATOR_VERSION}"
echo "CSV (FBC ${FBC_OCP_VERSION}):      ${CSV_NAME}"
echo "RHOSDT version:      ${RHOSDT_VERSION}"
echo

# Sets a pipeline param's default value, targeting the "default:" line that follows "- name: <param>".
set_pipeline_default() {
  local file=$1 param=$2 value=$3
  sed -Ei.bak "/^ *- name: ${param}$/,/default:/ s|default: .*|default: \"${value}\"|" "${file}"
  rm -f "${file}.bak"
}

E2E_PIPELINE="${DIR}/opentelemetry-operator-e2e-test-fbc-pipeline.yaml"
set_pipeline_default "${E2E_PIPELINE}" operator_version "${OPERATOR_VERSION}"
set_pipeline_default "${E2E_PIPELINE}" operator_otel_collector_version "${OPERATOR_VERSION}"
set_pipeline_default "${E2E_PIPELINE}" operator_targetallocator_version "${TARGETALLOCATOR_VERSION}"
set_pipeline_default "${E2E_PIPELINE}" otel_collector_version "${COLLECTOR_VERSION}"
set_pipeline_default "${E2E_PIPELINE}" otel_tests_branch "${TESTS_BRANCH}"
set_pipeline_default "${E2E_PIPELINE}" rhosdt_version "${RHOSDT_VERSION}"

UPGRADE_PIPELINE="${DIR}/opentelemetry-operator-upgrade-test-fbc-pipeline.yaml"
set_pipeline_default "${UPGRADE_PIPELINE}" operator_csv_version "${CSV_NAME}"
set_pipeline_default "${UPGRADE_PIPELINE}" collector_version "${COLLECTOR_VERSION}"
set_pipeline_default "${UPGRADE_PIPELINE}" ta_version "${TARGETALLOCATOR_VERSION}"
set_pipeline_default "${UPGRADE_PIPELINE}" otel_tests_branch "${TESTS_BRANCH}"

echo "Updated the defaults in:"
echo "  ${E2E_PIPELINE}"
echo "  ${UPGRADE_PIPELINE}"
echo "Review the diff, and check the IntegrationTestScenarios in konflux-release-data (application, names, OCP versions)."
