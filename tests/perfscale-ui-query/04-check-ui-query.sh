#!/bin/bash

max=1200
interval=10
wait_time=2
repeats=150 # with wait_time=2 will get 5 minutes of timeout

test_start=$(date)
results_file=test_run_$(date +%Y%m%d_%H%M%S).csv
dir=$(date +%Y%m%d_%H%M%S)
mkdir $dir

# Adding headder
echo "limit,request_time" >>$results_file

# Getting correct time to querries
end=$(date +%s)
start=$(($end - 3600))
start=$(echo "${start}000000")
end=$(echo "${end}000000")
echo $end
echo $start

for i in $(seq $interval $interval $max); do
  echo -e "\n$i =================================================================================="

  # Check if frotend pod is ready
  for r in $(seq $repeats); do
    running=$(oc get pods -l app.kubernetes.io/component=query-frontend -n test-perfscale | grep -c Running)
    if [[ $running == 1 ]]; then
      echo "Frontend pod is running"
      break
    else
      if [[ $r == $repeats ]]; then
        echo "It is too long for frontend pod to be ready - EXIT"
        echo "Test start: $test_start"
        echo "Test end:   $(date)"
        exit 1
      fi
    fi
    sleep $wait_time
  done

  oc delete job verify-traces -n test-perfscale
  cat ./content/verify-traces.yaml |
    sed "s/%LIMIT%/${i}/g" |
    sed "s/%START%/${start}/g" |
    sed "s/%END%/${end}/g" |
    oc create -f -
  pod=$(oc get pods -n test-perfscale --show-labels | grep job-name=verify-traces | cut -f 1 -d " ")

  # Check if job is compeleted
  for r in $(seq $repeats); do
    completions=$(oc get pod $pod -n test-perfscale | grep -c Completed)
    if [[ $completions == 1 ]]; then
      echo "Job is completed"
      break
    else
      if [[ $r == $repeats ]]; then
        echo "It is taking too long for job to finish"
        echo "Test start: $test_start"
        echo "Test end:   $(date)"
        exit 1
      fi
    fi
    sleep $wait_time
  done

  oc get pods -l app.kubernetes.io/component=query-frontend -n test-perfscale
  oc logs $pod -n test-perfscale >>$dir/$i.log
  request_time=$(oc logs $pod -n test-perfscale | grep "TIME_TOTAL" | tail -n 1 | cut -f 2 -d " ")
  echo "$i,$request_time" >>$results_file
done
test_end=$(date)

echo "Test start: $test_start"
echo "Test end:   $test_end"
