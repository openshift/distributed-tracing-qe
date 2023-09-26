#!/bin/bash
set -e

# Get the app route URL
app_url=$(oc -n kuttl-jaeger-otel-sidecar-app get route sample-app -o json | jq '.spec.host' -r)

# Make a curl request to the host URL
curl "$app_url/order"
