#!/bin/bash

oc extract -n kube-system secret/gcp-credentials --to=/tmp --confirm
if [ $? -ne 0 ]; then
    echo "Failed to fetch GCS service account json."
    exit 1
fi

GOOGLE_APPLICATION_CREDENTIALS_FILE="/tmp/service_account.json"

# Extract the project ID using jq
PROJECT_ID=$(jq -r .project_id "$GOOGLE_APPLICATION_CREDENTIALS_FILE")
if [ -z "$PROJECT_ID" ]; then
    echo "Failed to extract project_id from the JSON file."
    exit 1
fi

# Create a new secret with project-id as a literal
kubectl -n "$NAMESPACE" create secret generic gcp-secret \
    --from-file=key.json="$GOOGLE_APPLICATION_CREDENTIALS_FILE" \
    --from-literal=project-id="$PROJECT_ID"
if [ $? -ne 0 ]; then
    echo "Failed to create secret"
    exit 1
fi

echo "Script executed successfully."
