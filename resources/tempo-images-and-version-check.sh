#!/bin/bash
set -eu

# Variables for strings to check
#JAEGER_QUERY_VERSION=$(params.JAEGER_QUERY_VERSION)
#OPERATOR_VERSION=$(params.OPERATOR_VERSION)
#OPERATOR_TEMPO_VERSION=$(params.OPERATOR_TEMPO_VERSION)
#OPERATOR_TEMPO_QUERY_VERSION=$(params.OPERATOR_TEMPO_QUERY_VERSION)
#OPERAND_TEMPO_VERSION=$(params.OPERAND_TEMPO_VERSION)

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
echo "TEMPO IMAGE DETAILS AND VERSION INFO"
echo

export TEMPO_ICSP=https://raw.githubusercontent.com/openshift/distributed-tracing-qe/refs/heads/main/resources/tempo-icsp.yaml
curl -Lo /tmp/ImageContentSourcePolicy.yaml "$TEMPO_ICSP"

tempo_images=$(oc get deployment tempo-operator-controller -n openshift-tempo-operator -o yaml | grep -o "registry.redhat.io/rhosdt/.*" | sort | uniq)
[ $(echo "$tempo_images" | wc -l) -eq 6 ] || exit_error "Expected 6 images, found:\n$tempo_images"

oc project default

for image in $tempo_images; do
    oc image info "$image" --icsp-file /tmp/ImageContentSourcePolicy.yaml --filter-by-os linux/amd64
    echo

    random_name=$(generate_random_name)

    if [[ $image == *tempo-rhel8@* ]]; then
        log_cmd oc run $random_name --image=$image -- --version
        wait_for_pod_running $random_name default
        log_cmd oc logs pod/$random_name
        #check_strings_in_logs $random_name default "$OPERAND_TEMPO_VERSION"
    elif [[ $image == *tempo-gateway-rhel8* || $image == *tempo-gateway-opa-rhel8* || $image == *tempo-query-rhel8* ]]; then
        echo "SKIPPED: $image doesn't have a version command"
    elif [[ $image == *tempo-rhel8-operator@* ]]; then
        log_cmd oc run $random_name --image=$image -- version
        wait_for_pod_running $random_name default
        log_cmd oc logs pod/$random_name
        #check_strings_in_logs $random_name default "$OPERATOR_VERSION" "$OPERATOR_TEMPO_VERSION" "$OPERATOR_TEMPO_QUERY_VERSION"
    elif [[ $image == *tempo-jaeger-query-rhel8@* ]]; then
        log_cmd oc run $random_name --image=$image -- version
        wait_for_pod_running $random_name default
        log_cmd oc logs pod/$random_name
        #check_strings_in_logs $random_name default "$JAEGER_QUERY_VERSION"
    else
        log_cmd oc run $random_name --image=$image -- version
        wait_for_pod_running $random_name default
        log_cmd oc logs pod/$random_name
    fi

    echo
    echo
done
