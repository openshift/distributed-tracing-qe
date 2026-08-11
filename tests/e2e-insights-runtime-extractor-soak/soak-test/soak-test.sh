#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

iteration=0
while [ $iteration -le 120 ]; do
  "${SCRIPT_DIR}/extract.sh"
  sleep 30
  echo "iteration: ${iteration}"
  iteration=$(($iteration+1))
done
