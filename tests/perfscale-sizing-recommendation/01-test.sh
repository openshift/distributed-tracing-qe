#!/bin/bash

rate=5000

oc delete job generate-traces -n test-perfscale

cat ./content/05-generate-traces.yaml | sed "s/%RATE_NUMBER%/$rate/g" | oc create -f -
