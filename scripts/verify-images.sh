#!/bin/bash
set -eu

function log_cmd() {
    echo "\$ $*"
    "$@"
}
function exit_error() {
    >&2 echo -e "ERROR: $*"
    exit 1
}


echo "*Jaeger image Details*"
echo

jaeger_images=$(oc get deployment jaeger-operator -n openshift-distributed-tracing -o yaml | grep -o "registry.redhat.io/rhosdt/.*" | sed 's/registry.redhat.io/registry.stage.redhat.io/' | sort | uniq)
[ $(echo "$jaeger_images" | wc -l) -eq 8 ] || exit_error "Expected 8 images, found:\n$jaeger_images"

echo "{noformat}"
for image in $jaeger_images; do
    podman pull "$image" -q > /dev/null
    podman images "$image" --digests
    echo

    if [[ $image == *jaeger-es-index-cleaner-rhel8* || $image == *jaeger-es-rollover-rhel8* ]]; then
        echo "SKIPPED: $image doesn't have a version command"
    else
        log_cmd podman run --rm $image version
    fi

    echo
    echo
done
echo "{noformat}"

echo
echo
echo "*OpenTelemetry image Details*"
echo

otel_images=$(oc get deployment opentelemetry-operator-controller-manager -n openshift-opentelemetry-operator -o yaml | grep -o "registry.redhat.io/rhosdt/.*" | sed 's/registry.redhat.io/registry.stage.redhat.io/' | sort | uniq)
[ $(echo "$otel_images" | wc -l) -eq 3 ] || exit_error "Expected 2 images, found:\n$otel_images"

echo "{noformat}"
for image in $otel_images; do
    podman pull "$image" -q > /dev/null
    podman images "$image" --digests
    echo

    if [[ $image == *opentelemetry-rhel8-operator* ]]; then
        log_cmd podman run --rm $image |& head -n2
    elif [[ $image == *opentelemetry-target-allocator-rhel8* ]]; then
      echo "SKIPPED: $image doesn't have a version command"
    else
        log_cmd podman run --rm $image --version
    fi

    echo
    echo
done
echo "{noformat}"

echo
echo
echo "*Tempo image Details*"
echo

tempo_images=$(oc get deployment tempo-operator-controller -n openshift-tempo-operator -o yaml | grep -o "registry.redhat.io/rhosdt/.*" | sed 's/registry.redhat.io/registry.stage.redhat.io/' | sort | uniq)
[ $(echo "$tempo_images" | wc -l) -eq 5 ] || exit_error "Expected 5 images, found:\n$tempo_images"

echo "{noformat}"
for image in $tempo_images; do
    podman pull "$image" -q > /dev/null
    podman images "$image" --digests
    echo

    if [[ $image == *tempo-rhel8@* ]]; then
      log_cmd podman run --rm $image --version
    elif [[ $image == *tempo-gateway-rhel8* || $image == *tempo-gateway-opa-rhel8* ]]; then
      echo "SKIPPED: $image doesn't have a version command"
    else
      log_cmd podman run --rm $image version
    fi

    echo
    echo
done
echo "{noformat}"
