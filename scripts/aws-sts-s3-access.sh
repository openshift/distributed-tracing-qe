#!/bin/bash
set -euo pipefail

# Create a S3 bucket aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION
# Run the script with ./aws-sts-s3-access.sh TEMPO_NAME TEMPO_NAMESPACE

tempostack_name="$1"
oidc_provider=$(oc get authentication cluster -o json | jq -r '.spec.serviceAccountIssuer' | sed 's~http[s]*://~~g')
tempostack_ns="$2"
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)
region=us-east-2
cluster_id=$(oc get clusterversion -o jsonpath='{.items[].spec.clusterID}{"\n"}')
trust_rel_file="/tmp/$cluster_id-trust.json"
role_name="tracing-$tempostack_ns-$tempostack_name"

# Create a trust relationship file
cat > "$trust_rel_file" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${aws_account_id}:oidc-provider/${oidc_provider}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_provider}:sub": [
            "system:serviceaccount:${tempostack_ns}:tempo-${tempostack_name}"
         ]
       }
     }
   }
 ]
}
EOF

echo "Creating IAM role '$role_name' in account '$aws_account_id'..."
role_arn=$(aws iam create-role \
             --role-name "$role_name" \
             --assume-role-policy-document "file://$trust_rel_file" \
             --query Role.Arn \
             --output text)

echo "Attaching role policy 'AmazonS3FullAccess' to role '$role_name' with ARN '$role_arn'..."
aws iam attach-role-policy \
  --role-name "$role_name" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess"

echo "Role created and policy attached successfully!"
