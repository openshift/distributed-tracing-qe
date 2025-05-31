#!/bin/bash
set -uo pipefail

# --- Set the GCP & Kubernetes vars - MUST MATCH THE CREATION SCRIPT EXACTLY! ---
PROJECT_ID=$(gcloud config get-value project)
K8S_NAMESPACE="chainsaw-gmpmetrics" # Renamed for broader Kubernetes applicability
K8S_SA_NAME="chainsaw-gmpmetrics-sa"
GCP_SA_NAME="otel-gmpmetrics-key-auth-sa"
K8S_SECRET_NAME="gcp-service-account-key"

echo "--- Starting cleanup process for OpenTelemetry Service Account Key resources ---"
echo "  GCP Project ID: $PROJECT_ID"
echo "  Kubernetes Namespace: $K8S_NAMESPACE"
echo "  Kubernetes Service Account: $K8S_SA_NAME"
echo "  Google Cloud Service Account: $GCP_SA_NAME"
echo "  Kubernetes Secret: $K8S_SECRET_NAME"
echo "----------------------------------------------------------------------"

# --- 1. Revoke Google Cloud IAM Bindings and Delete Google Service Account ---

# Get the full email of the Google Service Account
GCP_SA_EMAIL="${GCP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# The 'workloadIdentityUser' role binding is removed as it's not applicable for direct key authentication.
# No need to remove `roles/iam.workloadIdentityUser` as it was never granted.

echo "Revoking Monitoring Metric Writer role from $GCP_SA_EMAIL..."
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role="roles/monitoring.metricWriter" \
  --quiet || true # Use || true to gracefully handle if binding doesn't exist

echo "Revoking Cloud Telemetry Metrics Writer role from $GCP_SA_EMAIL..."
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role="roles/telemetry.metricsWriter" \
  --quiet || true # Use || true to gracefully handle if binding doesn't exist

echo "Deleting Google Cloud Service Account: $GCP_SA_EMAIL..."
# Added --etag If-Match='*' for safer deletion, but make it optional with || true for idempotency
gcloud iam service-accounts delete "$GCP_SA_EMAIL" \
  --project "$PROJECT_ID" \
  --quiet || true

echo "--- Google Cloud IAM roles and Service Account successfully removed. ---"

# --- 2. Delete Kubernetes Resources ---

echo "Deleting Kubernetes Secret: $K8S_SECRET_NAME in namespace $K8S_NAMESPACE..."
kubectl delete secret "$K8S_SECRET_NAME" -n "$K8S_NAMESPACE" \
  --ignore-not-found=true || true # Ignore if Secret doesn't exist

echo "Deleting Kubernetes Service Account: $K8S_SA_NAME in namespace $K8S_NAMESPACE..."
kubectl delete serviceaccount "$K8S_SA_NAME" -n "$K8S_NAMESPACE" \
  --ignore-not-found=true || true # Ignore if SA doesn't exist

echo "Deleting Kubernetes namespace: $K8S_NAMESPACE..."
# For OpenShift, 'oc delete project' works. For generic Kubernetes, 'kubectl delete namespace'.
# Using 'kubectl' for broader compatibility.
kubectl delete namespace "$K8S_NAMESPACE" \
  --ignore-not-found=true \
  --wait=false || true

echo "--- Kubernetes resources deletion initiated. ---"
echo "Namespace deletion may take some time to complete in the background."

echo "----------------------------------------------------------------------"
echo "Cleanup script finished. All specified resources are being removed or have been removed."