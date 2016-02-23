#!/bin/bash

# Run smoke tests for PSMDB 

# suite definitions - first element is suite name
# followed by runSets 

# runSets:
#   default    - run the suite with default smoke config
#   se         - run the suite with all non-default storage engines
#   auth       - run the suite with the authentication
#   wiredTiger - run with wiredTiger storage engine
#   PerconaFT  - run with PerconaFT storage engine
#   rocksdb    - run with rocksdb storage engine
#   mmapv1     - run with mmapv1 storage engine

# suite name or runSets can have -- style options specified 
# which are passed to smoke

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
ssl --use-ssl,default
sslSpecial,default
tool,default,se
EOS

# smoke parameters
SMOKE_BASE="--continue-on-failure --clean-every=1"
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
    if [[ ${suiteElement} =~ ^([a-z0-9_]+)[[:space:]](.*)$ ]]; then
      suiteElementName=${BASH_REMATCH[1]}
      suiteElementOptions=${BASH_REMATCH[2]}
    else
      suiteElementName=${suiteElement}
      suiteElementOptions=""
    fi
    if [ ${suiteElementNumber} -eq 0 ]; then
      suite=${suiteElementName}
      suiteOptions=${suiteElementOptions}
    else
      suiteRunSet=${suiteElementName}
      suiteRunSetOptions=${suiteElementOptions}
      logOutputFilePrefix="smoke_${suite}_${suiteRunSet}"
      case "$suiteRunSet" in
        "default")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          smokeParams="${SMOKE_BASE} ${SMOKE_DEFAULT} --storageEngine=${DEFAULT_ENGINE} ${suiteOptions} ${suiteRunSetOptions} ${suite}"
          runSmoke "${smokeParams}" "$logOutputFile"
          ;;
        "auth")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          smokeParams="${SMOKE_BASE} ${SMOKE_AUTH} --storageEngine=${DEFAULT_ENGINE} ${suiteOptions} ${suiteRunSetOptions} ${suite}"
          runSmoke "${smokeParams}" "$logOutputFile"
          ;;
        "wiredTiger")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          smokeParams="${SMOKE_BASE} ${SMOKE_AUTH} --storageEngine=wiredTiger ${suiteOptions} ${suiteRunSetOptions} ${suite}"
          runSmoke "${smokeParams}" "$logOutputFile"
          ;;
        "PerconaFT")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          smokeParams="${SMOKE_BASE} ${SMOKE_AUTH} --storageEngine=PerconaFT ${suiteOptions} ${suiteRunSetOptions} ${suite}"
          runSmoke "${smokeParams}" "$logOutputFile"
          ;;
        "rocksdb")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          smokeParams="${SMOKE_BASE} ${SMOKE_AUTH} --storageEngine=rocksdb ${suiteOptions} ${suiteRunSetOptions} ${suite}"
          runSmoke "${smokeParams}" "$logOutputFile"
          ;;
        "mmapv1")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          smokeParams="${SMOKE_BASE} ${SMOKE_AUTH} --storageEngine=mmapv1 ${suiteOptions} ${suiteRunSetOptions} ${suite}"
          runSmoke "${smokeParams}" "$logOutputFile"
          ;;
        "se")
          for engine in "${ENGINES[@]}"; do
            if [ ! "${engine}" == "${DEFAULT_ENGINE}" ]; then
              logOutputFile="${logOutputFilePrefix}_${engine}_${trial}.log"
              smokeParams="${SMOKE_BASE} --storageEngine=${engine} ${SMOKE_SE} ${suiteOptions} ${suiteRunSetOptions} ${suite}"
              runSmoke "${smokeParams}" "$logOutputFile"
            fi
          done
          ;;
        *)
          echo "failed: Unknown runSet definition: ${suiteRunSet} for ${suite}" >> "smoke_unknown_${trial}.log"
          ;;
      esac
    fi
    ((suiteElementNumber++))
  done
done

