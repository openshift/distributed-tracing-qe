#!/bin/bash

oc project default
oc delete job generate-traces -n test-generate-traces
oc delete clusterrolebinding perfscale-tempo-monitoring-view 
oc delete tempostack tempostack -n test-perfscale
oc delete configmaps cluster-monitoring-config -n openshift-monitoring

BUCKET_NAME="skordas-tempostack-s3"
REGION="us-east-2"
aws s3 rb s3://$BUCKET_NAME --region $REGION --force

oc delete project test-perfscale
oc delete project test-generate-traces
