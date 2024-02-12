#!/bin/bash
set -eu

function log_cmd() {
    echo "\$ $*"
    "$@"
}


# This image is used to extract the channels
podman pull docker.io/nouchka/sqlite3 -q > /dev/null

# the path to the SQLite db changed in OCP v4.11
for ocp_version in 4.12 4.13 4.14 4.15 4.16; do
    echo "*OCP $ocp_version*"
    echo "{noformat}"
    log_cmd oc image extract \
        registry.stage.redhat.io/redhat/redhat-operator-index:v$ocp_version \
        --file=/var/lib/iib/_hidden/do.not.edit.db --insecure=true 2>/dev/null
    log_cmd podman run -v $(pwd)/do.not.edit.db:/index.db:z -ti nouchka/sqlite3 -header -column /index.db \
        "SELECT package_name, name, head_operatorbundle_name AS csv FROM channel WHERE package_name in ('jaeger-product', 'opentelemetry-product', 'tempo-product') ORDER BY package_name, name"
    rm do.not.edit.db
    echo "{noformat}"
    echo
done
