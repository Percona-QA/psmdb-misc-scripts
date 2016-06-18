#!/bin/bash

# Run smoke tests for PSMDB 3.0

basedir=$(cd "$(dirname "$0")" || exit; pwd)
# shellcheck source=run_smoke_resmoke_funcs.sh
source "${basedir}/run_smoke_resmoke_funcs.sh"

# suite definitions - first element is suite name
# followed by runSets 

# runSets:
#   default    - run the suite with default smoke config
#   se         - run the suite with all non-default storage engines
#   auth       - run the suite with authentication
#   wiredTiger - run with wiredTiger storage engine
#   PerconaFT  - run with PerconaFT storage engine
#   rocksdb    - run with rocksdb storage engine
#   mmapv1     - run with mmapv1 storage engine

# suite name or runSets can have -- style options specified 
# which are passed to smoke
#
# lines beginning one or more spaces followed by a $ denote shell commands to
# run before the preceding suite runSets are run.


readarray SUITES <<-EOS
aggregation --nopreallocj,default,auth,se
audit --nopreallocj,default,se
auth --nopreallocj,default,se
concurrency --nopreallocj,default,se
concurrency --nopreallocj --shell-write-mode compatibility,default,se
dbtest --nopreallocj,default,se
disk --nopreallocj,default
dur --nopreallocj,default
failPoint --nopreallocj,default,auth
gle --nopreallocj --auth,default,se
gle --nopreallocj --auth --shell-write-mode commands,default,se
jsCore --nopreallocj --shell-write-mode commands,se,default,auth
jsCore --nopreallocj --shell-write-mode compatibility,default,se
jsCore --shell-write-mode commands --small-oplog,default,se
mmap_v1 --nopreallocj,default
mongosTest --nopreallocj,default
multiVersion --nopreallocj,default
  $ rm -rf ${DBPATH}/install ${DBPATH}/multiversion
  $ python buildscripts/setup_multiversion_mongodb.py ${DBPATH}/install ${DBPATH}/multiversion "Linux/x86_64" "1.8" "2.0" "2.2" "2.4" "2.6"
  $ [[ ${PATH} == *"/data/multiversion"* ]] || export PATH=${PATH}:/data/multiversion 
noPassthrough --nopreallocj,default,se	
noPassthroughWithMongod --nopreallocj,default,se
parallel --nopreallocj,default,se	
parallel --nopreallocj --shell-write-mode compatibility,default,se	
replSets --nopreallocj,default,se,auth
repl --nopreallocj,default,se,auth
sharding --nopreallocj,default,se,auth
slow1 --nopreallocj,default,se
slow2 --nopreallocj,default,se
ssl --nopreallocj --use-ssl,default
sslSpecial --nopreallocj,default
tool --nopreallocj,default,se
EOS

# smoke parameters
SMOKE_BASE="--continue-on-failure --with-cleanbb"
SMOKE_DEFAULT=""
SMOKE_AUTH="--auth"
SMOKE_SE=""

run_system_validations

# trial number

if [ "$1" == "" ]; then
  echo "Usage ./run_smoke.sh {trial #}"
  exit 1;
fi
trial=$1

# main script

runSmoke() {
  local smokeParams=$1
  local logOutputFile=$2
  local suiteRawName=$3

  rm -rf "${DBPATH}/db/*"

  runPreprocessingCommands "${logOutputFile}" "${suiteRawName}"

  echo "Running Command: python buildscripts/smoke.py ${smokeParams}" | tee -a "${logOutputFile}"
  # shellcheck disable=SC2086
  python buildscripts/smoke.py ${smokeParams} 2>&1 | tee -a "${logOutputFile}"

}

for suite in "${SUITES[@]}"; do

  # skip lines begining with space
  if [[ "${suite}" == " "* ]]; then
    continue; 
  fi

  IFS=',' read -r -a suiteDefinition <<< "${suite}"
  suiteElementNumber=0

  for suiteElement in "${suiteDefinition[@]}"; do
    if [[ ${suiteElement} =~ ^([a-zA-Z0-9_]+)[[:space:]](.*)$ ]]; then
      suiteElementName=${BASH_REMATCH[1]}
      suiteElementOptions=${BASH_REMATCH[2]}
    else
      suiteElementName=${suiteElement}
      suiteElementOptions=""
    fi
    if [ ${suiteElementNumber} -eq 0 ]; then
      suite=${suiteElementName}
      suiteRawName=${suiteElement}
      suiteOptions=${suiteElementOptions}
      suiteLogTag=$(echo "${suiteElement}" | sed -r -e 's/ +/_/g' -e 's/-//g')
    else
      suiteRunSet=${suiteElementName}
      suiteRunSetOptions=${suiteElementOptions}
      logOutputFilePrefix="smoke_${suiteLogTag}_${suiteRunSet}"
      case "$suiteRunSet" in
        "default"|"auth")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          [ "${suiteRunSet}" == "default" ] && smokeParams=${SMOKE_DEFAULT}
          [ "${suiteRunSet}" == "auth" ] && smokeParams=${SMOKE_AUTH}
          smokeParams="${SMOKE_BASE} ${smokeParams} --storageEngine=${DEFAULT_ENGINE} ${suiteOptions} ${suiteRunSetOptions} ${suite}"
          runSmoke "${smokeParams}" "${logOutputFile}" "${suiteRawName}"
          ;;
        "wiredTiger"|"PerconaFT"|"rocksdb"|"mmapv1")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          if hasEngine "${suiteRunSet}"; then
            smokeParams="${SMOKE_BASE} ${SMOKE_SE} --storageEngine=${suiteRunSet} ${suiteOptions} ${suiteRunSetOptions} ${suite}"
            runSmoke "${smokeParams}" "${logOutputFile}" "${suiteRawName}"
          else
            echo "failed: Storage Engine runSet: ${suiteRunSet} requested for suite ${suite} but is not available." | tee -a "${logOutputFile}"
          fi
          ;;
        "se")
          for engine in "${ENGINES[@]}"; do
            if [ ! "${engine}" == "${DEFAULT_ENGINE}" ]; then
              logOutputFile="${logOutputFilePrefix}_${engine}_${trial}.log"
              smokeParams="${SMOKE_BASE} --storageEngine=${engine} ${SMOKE_SE} ${suiteOptions} ${suiteRunSetOptions} ${suite}"
              runSmoke "${smokeParams}" "${logOutputFile}" "${suiteRawName}"
            fi
          done
          ;;
        *)
          echo "failed: Unknown runSet definition: ${suiteRunSet} for ${suite}" | tee -a "smoke_unknown_${trial}.log"
          ;;
      esac
    fi
    ((suiteElementNumber++))
  done
done

# output summary report

find . -type f -name "*_${trial}.log" \
  -print \
  -exec sh -c 'logfile="$1"; grep -E -A9999 "^[0-9]+ tests succeeded" "${logfile}" | sed -e "s/^/    /"' _ "{}" \; \
  -exec echo "" \; \
  | tee "smoke_summary_${trial}.log"

