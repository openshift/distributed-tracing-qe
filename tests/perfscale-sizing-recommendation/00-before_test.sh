#!/bin/bash

# Usage:
# bash 00-before_test.sh small 
# bash 00-before_test.sh medium
# bash 00-before_test.sh heavy
# to create specific CR - please check ./content/03-tempostack_*.yaml files for more details.

# set -o errexit
# set -o pipefail

sizing="${1:-'small'}"

sleep_time=30
r=10 # Number of repeats

function log_task {
  echo -e "\n------====== $1 ======------"
}

function is_pod_ready {
  ns=$1
  label=$2
  ready=1 #true
  containers=$(oc get pods -n $ns -l $label -o jsonpath={.items[0].status.containerStatuses})
  number_of_elements=$(echo $containers | jq ". | length")
  ((number_of_elements--)) # to get max index
  for i in $(seq 0 $number_of_elements)
  do
    container_name=$(echo $containers | jq -r ".[$i].name")
    container_status=$(echo $containers | jq -r ".[$i].ready")
    if [[ $container_status != true ]]
    then
      ready=0 #false
    fi
  done
  echo $ready
}

### Untaint Infra node
log_task "UnTaint infra node"
for node in $(oc get nodes | grep infra | cut -f 1 -d ' '); do
  oc adm taint nodes $node node-role.kubernetes.io/infra-
done

### NAMESPACE ###
log_task "CREATING NAMESPACE"
oc create -f ./content/01-namespace.yaml

for i in $(seq $r)
do
  status=$(oc get namespace test-perfscale -o jsonpath={.status.phase})
  echo "Try #$i/$r Status of namespace: $status"
  if [[ $status == "Active" ]]
  then
    echo "Namespace test-perfscale is ready"
    break
  else
    if [[ $i == $r ]]
    then
      echo "Namespace test-perfscale is not ready after $r attempts!"
      oc get project test-perfscale
      echo "Exiting"
      exit 1
    fi
    echo "Namespace test-perfscale is not ready. Waiting for next $sleep_time seconds"
    sleep $sleep_time
  fi
done

### PREPARE BUCKET ###
log_task "Create bucket"
bash create-bucket.sh

### WORKLOAD MONITORING ###
log_task "Workload Monitoring"
oc create -f ./content/02-workload-monitoring.yaml

for i in $(seq $r)
do
  name=$(oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath={.metadata.name})
  echo "Try #$i/$r name of new configmap: $name"
  if [[ $name == "cluster-monitoring-config" ]]
  then
    echo "Configmap cluster-monitoring-config is ready"
    break
  else
    if [[ $i == $r ]]
    then
      echo "ConfigMap is not ready after $r attempts!"
      oc get configmap -n openshift-monitoring
      echo "Exiting"
      exit 1
    fi
    echo "Configmap cluster-monitoring-config is not ready. Wating for next $sleep_time seconds"
    sleep $sleep_time
  fi
done


### PREPARE TEMPOSTACK ###
log_task "TempoStack"
case $sizing in
  small)
     oc create -f ./content/03-tempostack_small.yaml
     ;;

  medium)
    oc create -f ./content/03-tempostack_medium.yaml
    ;;

  heavy)
    oc create -f ./content/03-tempostack_heavy.yaml
    ;;

  *)
    echo "!! Unknown parameter. Please use small/medium/heavy !!"
    echo "!! Run 'bash 02-after_test_cleaning.sh' to clean leftovers"
    exit 1
    ;;
esac
sleep 5

for i in $(seq $r)
do
  status_compactor=$(is_pod_ready test-perfscale app.kubernetes.io/component=compactor)
  status_distributor=$(is_pod_ready test-perfscale app.kubernetes.io/component=distributor)
  status_ingester=$(is_pod_ready test-perfscale app.kubernetes.io/component=ingester)
  status_querier=$(is_pod_ready test-perfscale app.kubernetes.io/component=querier)
  status_frontend=$(is_pod_ready test-perfscale app.kubernetes.io/component=query-frontend)
  echo "Try #$i/$r Status of:"
  echo "  Compactor pod ready:   $status_compactor"
  echo "  Distributor pod ready: $status_distributor"
  echo "  Ingester pod ready:    $status_ingester"
  echo "  Querier pod ready:     $status_querier"
  echo "  Frontend pod ready:    $status_frontend"
  if [[ $status_compactor == "1" ]] && [[ $status_distributor == "1" ]] && [[ $status_ingester == "1" ]] && [[ $status_querier == "1" ]] && [[ $status_frontend == "1" ]]
  then
    echo "TempoStack is ready"
    break
  else
    if [[ $i == $r ]]
    then
      echo "TempoStack is not ready after $r attempts!"
      oc get pods -n test-perfscale
      echo "Exiting"
      exit 1
    fi
    echo "TempoStack is not ready. Waiting for next $sleep_time seconds"
    sleep $sleep_time
  fi
done

### PREPARE CLUSTERROLEBINDING ###
log_task "ClusterRoleBinding"
oc create -f ./content/04-clusterrolebinding.yaml

### Taint infra node
log_task "Taint infra node"
for node in $(oc get nodes | grep infra | cut -f 1 -d ' '); do
  oc adm taint nodes $node node-role.kubernetes.io/infra=reserved:NoSchedule
done
