#!/bin/bash
set -euo pipefail

# --- User-configurable GCP & Kubernetes Vars ---
PROJECT_ID=$(gcloud config get-value project)
K8S_NAMESPACE="chainsaw-gmpmetrics" # Renamed for broader Kubernetes applicability
K8S_SA_NAME="chainsaw-gmpmetrics-sa"
GCP_SA_NAME="otel-gmpmetrics-key-auth-sa"
GCP_SA_KEY_FILE="/tmp/${GCP_SA_NAME}-key.json" # Path where the service account key will be temporarily saved
K8S_SECRET_NAME="gcp-service-account-key" # Name of the Kubernetes Secret to create

echo "--- Starting OpenTelemetry Service Account Key Authentication setup (via Kubernetes Secret) ---"
echo "  GCP Project ID: $PROJECT_ID"
echo "  Kubernetes Namespace: $K8S_NAMESPACE"
echo "  Kubernetes Service Account: $K8S_SA_NAME"
echo "  Google Cloud Service Account for Key Auth: $GCP_SA_NAME"
echo "  Service Account Key File will be temporarily saved to: $GCP_SA_KEY_FILE"
echo "  Kubernetes Secret Name: $K8S_SECRET_NAME"
echo "---------------------------------------------------------------------------------"

# --- 1. Create Kubernetes Namespace and Service Account ---
echo "Creating Kubernetes namespace: $K8S_NAMESPACE"
kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - || true

echo "Creating Kubernetes Service Account: $K8S_SA_NAME in namespace $K8S_NAMESPACE"
kubectl create serviceaccount "$K8S_SA_NAME" -n "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - || true

# --- 2. Create Google Cloud Service Account and Grant IAM Roles ---
echo "Creating Google Cloud Service Account: $GCP_SA_NAME"
GCP_SA_EMAIL=$(gcloud iam service-accounts create "$GCP_SA_NAME" \
  --display-name="OpenTelemetry GMP Metrics Service Account (Key Auth)" \
  --project "$PROJECT_ID" \
  --format='value(email)' \
  --quiet)

# Wait for the service account to be ready
echo "Waiting for Google Cloud service account $GCP_SA_EMAIL to be ready..."
MAX_RETRIES=10
RETRY_COUNT=0
while ! gcloud iam service-accounts describe "$GCP_SA_EMAIL" --project "$PROJECT_ID" &> /dev/null; do
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "Error: Google Cloud service account $GCP_SA_EMAIL not found after $MAX_RETRIES retries. Exiting."
    exit 1
  fi
  echo "Google Cloud service account not yet available. Retrying in 5 seconds..."
  sleep 5
  RETRY_COUNT=$((RETRY_COUNT + 1))
done
echo "Google Cloud service account $GCP_SA_EMAIL is ready."

echo "Granting Monitoring Metric Writer role to $GCP_SA_EMAIL..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role="roles/monitoring.metricWriter" \
  --quiet

echo "Granting Cloud Telemetry Metrics Writer role to $GCP_SA_EMAIL..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role="roles/telemetry.metricsWriter" \
  --quiet

echo "--- GCP IAM permissions configured for $GCP_SA_EMAIL. ---"

# --- 3. Create and Download Service Account Key File ---
echo "Creating and downloading JSON key file for $GCP_SA_EMAIL to $GCP_SA_KEY_FILE"
gcloud iam service-accounts keys create "$GCP_SA_KEY_FILE" \
  --iam-account "$GCP_SA_EMAIL" \
  --project "$PROJECT_ID" \
  --quiet

echo "Service Account key file created successfully at: $GCP_SA_KEY_FILE"

# --- 4. Create Kubernetes Secret from the Service Account Key File ---
echo "Creating Kubernetes Secret: $K8S_SECRET_NAME in namespace $K8S_NAMESPACE from $GCP_SA_KEY_FILE"
# The secret key will be 'key.json' by default when using --from-file
kubectl create secret generic "$K8S_SECRET_NAME" \
  --from-file="key.json=$GCP_SA_KEY_FILE" \
  --namespace="$K8S_NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Cleaning up local temporary credential file: $GCP_SA_KEY_FILE"
#rm "$GCP_SA_KEY_FILE"
