#!/bin/bash
set -eu

# Variables for strings to check
#OPERATOR_VERSION=$(params.OPERATOR_VERSION)
#OPERATOR_OTEL_COLLECTOR_VERSION=$(params.OPERATOR_OTEL_COLLECTOR_VERSION)
#OPERATOR_TARGETALLOCATOR_VERSION=$(params.OPERATOR_TARGETALLOCATOR_VERSION)
#OTEL_COLLECTOR_VERSION=$(params.OTEL_COLLECTOR_VERSION)

function log_cmd() {
    echo "\$ $*"
    "$@"
}
function exit_error() {
    >&2 echo -e "ERROR: $*"
    exit 1
}

function generate_random_name() {
    echo "random-name-$RANDOM"
}

function wait_for_pod_running() {
    local pod_name=$1
    local namespace=$2
    while true; do
        pod_status=$(oc get pod $pod_name -n $namespace -o jsonpath='{.status.phase}')
        if [ "$pod_status" == "Running" ]; then
            break
        elif [ "$pod_status" == "Failed" ] || [ "$pod_status" == "Unknown" ]; then
            exit_error "Pod $pod_name failed to start. Status: $pod_status"
        fi
        sleep 2
    done
}

function check_strings_in_logs() {
    local pod_name=$1
    local namespace=$2
    shift 2
    local strings=("$@")

    logs=$(oc logs pod/$pod_name -n $namespace)
    for string in "${strings[@]}"; do
        if ! echo "$logs" | grep -q "$string"; then
            exit_error "String '$string' not found in logs of pod $pod_name"
        fi
    done
}

echo
echo
echo "OPENTELEMETRY IMAGE DETAILS AND VERSION INFO"
echo

export OTEL_ICSP=https://raw.githubusercontent.com/os-observability/konflux-opentelemetry/refs/heads/main/.tekton/integration-tests/resources/ImageContentSourcePolicy.yaml
curl -Lo /tmp/ImageContentSourcePolicy.yaml "$OTEL_ICSP"

otel_images=$(oc get deployment opentelemetry-operator-controller-manager -n openshift-opentelemetry-operator -o yaml | grep -o "registry.redhat.io/rhosdt/.*" | sort | uniq)
[ $(echo "$otel_images" | wc -l) -eq 3 ] || exit_error "Expected 3 images, found:\n$otel_images"

oc project default

for image in $otel_images; do
    oc image info "$image" --icsp-file /tmp/ImageContentSourcePolicy.yaml --filter-by-os linux/amd64
    echo

    random_name=$(generate_random_name)

    if [[ $image == *opentelemetry-rhel8-operator* ]]; then
        log_cmd oc run $random_name --image=$image
        wait_for_pod_running $random_name default
        log_cmd oc logs pod/$random_name | head -n 2
        #check_strings_in_logs $random_name default $OPERATOR_VERSION $OPERATOR_OTEL_COLLECTOR_VERSION $OPERATOR_TARGETALLOCATOR_VERSION
    elif [[ $image == *opentelemetry-target-allocator-rhel8* ]]; then
        echo "SKIPPED: $image doesn't have a version command"
    else
        log_cmd oc run $random_name --image=$image -- --version
        wait_for_pod_running $random_name default
        log_cmd oc logs pod/$random_name
        #check_strings_in_logs $random_name default $OTEL_COLLECTOR_VERSION
    fi

    echo
    echo
done