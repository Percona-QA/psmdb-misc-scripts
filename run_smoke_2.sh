#!/bin/bash

# Run smoke tests for PSMDB 

# suite definitions - first element is suite 
# followed by options

# options:
# default - run the suite with default smoke config (mmapv1)
# se - run the suite with all other storage engines
# auth - run the suite with the --auth parameter

readarray SUITES <<-'EOS'
aggregation,default,auth,se
auth,default,se
concurrency,default,se
concurrency_compatibility,default,se
dbtest,default,se
disk,default
durability,default
failpoints,default,auth
gle_auth,default,se
gle_auth_write_cmd,default,se
jsCore,se,default,auth
jsCore_compatibility,default,se
jsCore_small_oplog,default,se
mmap,default
mongosTest,default
multiversion,default
noPassthrough,default,se	
noPassthroughWithMongod,se
noPassthrough,se
parallel,default,se	
parallel_compatibility,default,se
replicasets,default,se,auth
replication,default,se,auth
sharding,default,se,auth
slow1,default,se
slow2,default,se
ssl,default
sslSpecial,default
tool,default,se
EOS

# smoke parameters
SMOKE_BASE="--continue-on-failure"
SMOKE_DEFAULT=""
SMOKE_AUTH="--auth"
SMOKE_SE=""

# detect engines
if [ ! -x './mongod' ]; then
  echo "Could not find ./mongod; make sure you are running this from the root build directory."
  exit 1;
fi
ENGINES=()
DEFAULT_ENGINE=$(./mongod --help | grep storageEngine | perl -ne 'm/\(=([^\)]+)\)/;print $1')
ENGINES+=(${DEFAULT_ENGINE})
for engine in mmapv1 wiredTiger PerconaFT rocksdb; do
  if [ ! "${engine}" == "${DEFAULT_ENGINE}" ]; then
    if ./mongod --help | grep -q "${engine}"; then
      ENGINES+=("${engine}")
    fi
  fi
done

# main script

if [ "$1" == "" ]; then
  echo "Usage ./run_smoke.sh {trial #}"                                                                               
  exit 1;                                                                                                             
fi                                                                                                                    
trial=$1                                                                                                              

# fix for auth tests
if ! ls jstests/libs/key* > /dev/null 2>&1; then
  echo "Run from the root build directory."
  exit 1;
fi

chmod 400 jstests/libs/key*                                                                                           

runSmoke() {
  local smokeParams=$1
  local logOutputFile=$2
  python buildscripts/smoke.py ${smokeParams} 2>&1 | tee "${logOutputFile}"
}

for suite in "${SUITES[@]}"; do
  IFS=',' read -r -a suiteDefinition <<< "${suite}"
  suiteElementNumber=0
  for suiteElement in "${suiteDefinition[@]}"; do
    if [ ${suiteElementNumber} -eq 0 ]; then
      suite=${suiteElement}
    else
      suiteOption=${suiteElement}
      logOutputFilePrefix="smoke_${suite}_${suiteOption}"
      case "$suiteOption" in
        "default")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          smokeParams="${SMOKE_BASE} ${SMOKE_DEFAULT} --storageEngine=${DEFAULT_ENGINE} ${suite}"
          runSmoke "${smokeParams}" "$logOutputFile"
          ;;
        "auth")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          smokeParams="${SMOKE_BASE} ${SMOKE_AUTH} --storageEngine=${DEFAULT_ENGINE} ${suite}"
          runSmoke "${smokeParams}" "$logOutputFile"
          ;;
        "se")
          for engine in "${ENGINES[@]}"; do
            if [ ! "${engine}" == "${DEFAULT_ENGINE}" ]; then
              logOutputFile="${logOutputFilePrefix}_${engine}_${trial}.log"
              smokeParams="${SMOKE_BASE} --storageEngine=${engine} ${SMOKE_SE} ${suite}"
              runSmoke "${smokeParams}" "$logOutputFile"
            fi
          done
          ;;
      esac
    fi
    ((suiteElementNumber++))
  done
done

