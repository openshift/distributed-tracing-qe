#!/bin/bash

rate=40 # traces per second
runtime=4200 # Time in seconds
tracecount=$(($rate*$runtime))

oc delete job generate-traces -n test-generate-traces

cat ./content/05-generate-traces.yaml \
| sed "s/%RATE_NUMBER%/$rate/g" \
| sed "s/%RUN_TIME%/${runtime}s/g" \
| sed "s/%TRACE_COUNT%/$tracecount/g" \
| oc create -f -
