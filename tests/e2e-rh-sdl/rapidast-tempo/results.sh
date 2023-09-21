#!/bin/bash

# Temp directory to store generated pod yaml
TMP_DIR=/tmp

# Where to store sync'd results -- defaults to current dir
ARTIFACT_DIR=${ARTIFACT_DIR}

# Name for rapiterm pod
RANDOM_NAME=rapiterm-$RANDOM

# Name of PVC in RapiDAST Resource, i.e. which PVC to mount to grab results
PVC=rapidast-pvc

IMAGE_REPOSITORY=quay.io/redhatproductsecurity/rapidast-term

IMAGE_TAG=latest

cat <<EOF > $TMP_DIR/$RANDOM_NAME
apiVersion: v1
kind: Pod
metadata:
  name: $RANDOM_NAME
  namespace: rapidast-tempo
spec:
  containers:
    - name: terminal
      image: '$IMAGE_REPOSITORY:$IMAGE_TAG'
      command: ['sleep', '300']
      imagePullPolicy: Always
      volumeMounts:
        - name: results-volume
          mountPath: /zap/results/
      resources:
        limits:
          cpu: 100m
          memory: 500Mi
        requests:
          cpu: 50m
          memory: 100Mi
  volumes:
    - name: results-volume
      persistentVolumeClaim:
        claimName: $PVC
EOF

kubectl apply -f $TMP_DIR/$RANDOM_NAME
rm $TMP_DIR/$RANDOM_NAME
kubectl -n rapidast-tempo wait --for=condition=Ready pod/$RANDOM_NAME
kubectl -n rapidast-tempo cp $RANDOM_NAME:/zap/results $ARTIFACT_DIR
kubectl -n rapidast-tempo delete pod $RANDOM_NAME

# Function to search for zap-report.json recursively
search_for_zap_report() {
  local dir="$1/tempo"
  local found=0
  while IFS= read -r -d '' file; do
    if [[ "$file" == *"zap-report.json" ]]; then
      found=1
      if grep -q '"riskdesc": "High' "$file"; then
        echo "Found 'zap-report.json' containing 'riskdesc': 'High' in $file, failing..."
        exit 1
      else
        echo "Found 'zap-report.json' in $file, but it does not contain 'riskdesc': 'High'"
      fi
    fi
  done < <(find "$dir" -type f -name "zap-report.json" -print0)
  
  if [[ "$found" -eq 0 ]]; then
    echo "No 'zap-report.json' files found in subdirectories of $dir, failing..."
    exit 1
  fi
}

# Search for zap-report.json in subdirectories of $ARTIFACT_DIR
search_for_zap_report "$ARTIFACT_DIR"
