#!/bin/bash
set -euo pipefail

NAMESPACE="spring-boot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Deploying Spring Boot workload to namespace ${NAMESPACE}..."

# Create namespace (idempotent)
oc create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

# Deploy workload
oc apply -f "${SCRIPT_DIR}/spring-boot-deployment.yaml"
oc apply -f "${SCRIPT_DIR}/spring-boot-service.yaml"

echo "Spring Boot deployment applied in namespace ${NAMESPACE}."
