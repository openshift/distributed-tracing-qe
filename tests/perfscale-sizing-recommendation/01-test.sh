#!/bin/bash

rate=1000

oc delete job generate-traces -n test-generate-traces

cat ./content/05-generate-traces.yaml | sed "s/%RATE_NUMBER%/$rate/g" | oc create -f -
