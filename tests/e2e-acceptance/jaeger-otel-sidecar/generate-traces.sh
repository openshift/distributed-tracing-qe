#!/bin/bash
set -e

# Get the app route URL
app_url=$(oc -n kuttl-jaeger-otel-sidecar-app get route sample-app -o json | jq '.spec.host' -r)

# Make a curl request to the host URL
while true; do
  response=$(curl --write-out "%{http_code}" --silent --output /dev/null "$app_url/order")

  if [[ $response -eq 200 ]]; then
    echo "Successfully connected to $app_url/order"
    break
  else
    echo "Failed to connect to $app_url/order. Retrying..."
    sleep 5  # Wait for 5 seconds before retrying
  fi
done
