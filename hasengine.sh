#!/bin/bash

# Does the mongod in the current directory support a given storage engine?

# Example: ../psmdb-misc-scripts/hasengine.sh rocksdb

basedir=$(cd "$(dirname "$0")" || exit; pwd)
# shellcheck source=run_smoke_resmoke_funcs.sh
source "${basedir}/run_smoke_resmoke_funcs.sh"

if hasEngine "$1"; then
  echo "mongod has engine $1"
  exit 0
else
 echo "mongod does not have engine $1"
 exit 1
fi 

