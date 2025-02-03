#!/bin/bash

# Fetch AWS credentials based on CLUSTER_PROFILE_DIR variable
if [ -n "${CLUSTER_PROFILE_DIR}" ]; then
    AWS_ACCESS_KEY_ID=$(grep "aws_access_key_id=" "${CLUSTER_PROFILE_DIR}/.awscred" | cut -d '=' -f2)
    AWS_SECRET_ACCESS_KEY=$(grep "aws_secret_access_key=" "${CLUSTER_PROFILE_DIR}/.awscred" | cut -d '=' -f2)
else
    AWS_ACCESS_KEY_ID=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_access_key_id' | base64 -d)
    if [ $? -ne 0 ]; then
        echo "Failed to fetch AWS_ACCESS_KEY_ID"
        exit 1
    fi

    AWS_SECRET_ACCESS_KEY=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_secret_access_key' | base64 -d)
    if [ $? -ne 0 ]; then
        echo "Failed to fetch AWS_SECRET_ACCESS_KEY"
        exit 1
    fi
fi

# Create the Kubernetes secret
oc -n $NAMESPACE create secret generic aws-credentials --from-literal=access_key_id=${AWS_ACCESS_KEY_ID} --from-literal=secret_access_key=${AWS_SECRET_ACCESS_KEY}
if [ $? -ne 0 ]; then
    echo "Failed to create AWS credentials secret"
    exit 1
fi

echo "AWS secret aws-credentials created successfully"
