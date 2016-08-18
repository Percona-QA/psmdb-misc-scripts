#!/bin/bash

# Run resmoke test suites for PSMDB 3.2 

basedir=$(cd "$(dirname "$0")" || exit; pwd)
# shellcheck source=run_smoke_resmoke_funcs.sh
source "${basedir}/run_smoke_resmoke_funcs.sh"

# suite definitions - first element is suite name
# followed by runSets 

# runSets:
#   all        - run with all storage engines
#   auth       - run the suite with authentication
#   default    - run the suite with default resmoke config
#   nosuite    - run without suites option (just use args)
#   mmapv1     - run with mmapv1 storage engine
#   PerconaFT  - run with PerconaFT storage engine
#   rocksdb    - run with rocksdb storage engine
#   inMemory   - run with inMemory storage engine
#   se         - run the suite with all non-default storage engines
#   wiredTiger - run with wiredTiger storage engine
#
#
# suite name or runSets can have options specified after a space
# which are passed to resmoke.py
#
# If the suite name contains a preceeding '!' then no
# 'suites' parameter is used (just the -- style options)
#
# if the suite name's options contain --suites then that
# option will be used in place of the suite name
#
# indented lines beginning with a $ denote shell commands to run
# before the preceding suite runSets are run.

readarray SUITES <<-EOS
aggregation,mmapv1,wiredTiger,PerconaFT,rocksdb
aggregation_auth,default
audit,mmapv1,wiredTiger,PerconaFT,rocksdb
auth,mmapv1,wiredTiger,PerconaFT,rocksdb
auth_audit,mmapv1,wiredTiger,PerconaFT,rocksdb
bulk_gle_passthrough,mmapv1,wiredTiger,PerconaFT,rocksdb
concurrency,mmapv1,wiredTiger,rocksdb
concurrency_replication,mmapv1,wiredTiger,PerconaFT,rocksdb
concurrency_sharded,mmapv1,wiredTiger,rocksdb
concurrency_sharded_sccc,mmapv1,wiredTiger,PerconaFT,rocksdb
!concurrency_simultaneous --executor=concurrency jstests/concurrency/fsm_all_simultaneous.js,mmapv1,wiredTiger,rocksdb
dbtest,mmapv1,wiredTiger,PerconaFT,rocksdb
disk,default
dur_jscore_passthrough,default
durability,default,default
failpoints,default
failpoints_auth,default
gle_auth --shellWriteMode=legacy --shellReadMode=legacy,mmapv1,wiredTiger,PerconaFT,rocksdb
gle_auth --shellWriteMode=commands,mmapv1,wiredTiger,PerconaFT,rocksdb
gle_auth_basics_passthrough --shellWriteMode=legacy --shellReadMode=legacy,mmapv1,wiredTiger,PerconaFT,rocksdb
gle_auth_basics_passthrough --shellWriteMode=commands,mmapv1,wiredTiger,PerconaFT,rocksdb
core,mmapv1,wiredTiger,PerconaFT,rocksdb
core_auth,default
core --shellReadMode=legacy --shellWriteMode=compatibility,mmapv1,wiredTiger,PerconaFT,rocksdb
core_small_oplog,mmapv1,wiredTiger,PerconaFT,rocksdb
core_small_oplog_rs,mmapv1,wiredTiger,PerconaFT,rocksdb
jstestfuzz,mmapv1,wiredTiger,PerconaFT,rocksdb
jstestfuzz_replication,wiredTiger,PerconaFT,rocksdb
jstestfuzz_sharded,wiredTiger,PerconaFT,rocksdb
mmap,mmapv1
mongo_test,default
multiversion,default
  $ rm -rf ${DBPATH}/install ${DBPATH}/multiversion
  $ python buildscripts/setup_multiversion_mongodb.py ${DBPATH}/install ${DBPATH}/multiversion "Linux/x86_64" "2.4" "2.6" "3.0" "3.2.1"
  $ [[ ${PATH} == *"/data/multiversion"* ]] || export PATH=${PATH}:/data/multiversion
no_passthrough,mmapv1,wiredTiger,PerconaFT,rocksdb
no_passthrough_with_mongod,mmapv1,wiredTiger,PerconaFT,rocksdb
parallel,mmapv1,wiredTiger,PerconaFT,rocksdb
parallel --shellReadMode=legacy --shellWriteMode=compatibility,mmapv1,wiredTiger,PerconaFT,rocksdb
replica_sets,mmapv1,wiredTiger,PerconaFT,rocksdb
replica_sets_auth,default
replication,mmapv1,wiredTiger,PerconaFT,rocksdb
replication_auth,default
sharding,mmapv1,wiredTiger,rocksdb
sharding_auth,default
sharding_gle_auth_basics_passthrough --shellWriteMode=legacy --shellReadMode=legacy,mmapv1,wiredTiger,PerconaFT,rocksdb
sharding_gle_auth_basics_passthrough --shellWriteMode=commands,mmapv1,wiredTiger,PerconaFT,rocksdb
sharding_jscore_passthrough,mmapv1,wiredTiger,PerconaFT,rocksdb
sharding_legacy_multiversion,default
  $ rm -rf ${DBPATH}/install ${DBPATH}/multiversion
  $ python buildscripts/setup_multiversion_mongodb.py ${DBPATH}/install ${DBPATH}/multiversion "Linux/x86_64" "2.4" "2.6" "3.0" "3.2.1"
  $ [[ ${PATH} == *"/data/multiversion"* ]] || export PATH=${PATH}:/data/multiversion
slow1,mmapv1,wiredTiger,PerconaFT,rocksdb
slow2,mmapv1,wiredTiger,PerconaFT,rocksdb
ssl,default
ssl_special,default
tool,mmapv1,wiredTiger,PerconaFT,rocksdb
unittests,default
EOS

# smoke parameters
RESMOKE_JOBS=$(grep -cw ^processor /proc/cpuinfo)
RESMOKE_BASE="--continueOnFailure --jobs=${RESMOKE_JOBS} --shuffle"
RESMOKE_DEFAULT=""
RESMOKE_AUTH="--auth"
RESMOKE_SE=""

run_system_validations

# trial number

if [ "$1" == "" ]; then
  echo "Usage ./run_smoke.sh {trial #}"
  exit 1;
fi
trial=$1

# main script

runResmoke() {
  local resmokeParams=$1
  local logOutputFile=$2
  local suiteRawName=$3

  rm -rf "${DBPATH}/*"

  runPreprocessingCommands "${logOutputFile}" "${suiteRawName}"

  echo "Running Command: buildscripts/resmoke.py ${resmokeParams}" | tee -a "${logOutputFile}" 
  # shellcheck disable=SC2086
  python buildscripts/resmoke.py ${resmokeParams} 2>&1 | tee -a "${logOutputFile}"

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
      suiteRawName=${suite}
      suiteOptions=${suiteElementOptions}
      suiteLogTag=$(echo "${suiteElement}" | sed -r -e 's/ +/_/g' -e 's/[-!]//g')

      if [[ "${suite}" == *"!"* ]]; then
        useSuitesOption=false
        suite=${suite#!}
      elif [[ "${suiteOptions}" == *"--suites"* ]]; then
        useSuitesOption=false
      else
        useSuitesOption=true
      fi

    else

      suiteRunSet=${suiteElementName}
      suiteRunSetOptions=${suiteElementOptions}
      logOutputFilePrefix="resmoke_${suiteLogTag}_${suiteRunSet}"

      case "$suiteRunSet" in

        "default"|"auth")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          echo "Suite Definition: ${suiteRawName},${suiteElement}" | tee -a "${logOutputFile}"
          [ "${suiteRunSet}" == "default" ] && resmokeParams=${RESMOKE_DEFAULT}
          [ "${suiteRunSet}" == "auth" ] && resmokeParams=${RESMOKE_AUTH}
          resmokeParams="${RESMOKE_BASE} ${resmokeParams} ${suiteOptions} ${suiteRunSetOptions}"
          if $useSuitesOption; then
            resmokeParams="${resmokeParams} --suites=${suite}"
          fi
          runResmoke "${resmokeParams}" "$logOutputFile" "${suiteRawName}"

          ;;
        "wiredTiger"|"PerconaFT"|"rocksdb"|"mmapv1"|"inMemory")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          echo "Suite Definition: ${suiteRawName},${suiteElement}" | tee -a "${logOutputFile}"
          if hasEngine "${suiteRunSet}"; then
            resmokeParams="${RESMOKE_BASE} ${RESMOKE_SE} --storageEngine=${suiteRunSet} ${suiteOptions} ${suiteRunSetOptions}"
            if $useSuitesOption; then
              resmokeParams="${resmokeParams} --suites=${suite}"
            fi
            runResmoke "${resmokeParams}" "$logOutputFile" "${suiteRawName}"
          else
            echo "failed: Storage Engine runSet: ${suiteRunSet} requested for suite ${suite} but is not available." | tee -a "${logOutputFile}"
          fi
          ;;
        "se")
          for engine in "${ENGINES[@]}"; do
            if [ ! "${engine}" == "${DEFAULT_ENGINE}" ]; then
              logOutputFile="${logOutputFilePrefix}_${engine}_${trial}.log"
              if [[ -z "${suiteRunSetOptions}" ]]; then
                suiteDefinition="${suiteRawName},${engine}"
              else
                suiteDefinition="${suiteRawName},${engine} ${suiteRunSetOptions}"
              fi
              echo "Suite Definition: ${suiteDefinition}" | tee -a "${logOutputFile}"
              resmokeParams="${RESMOKE_BASE} --storageEngine=${engine} ${RESMOKE_SE} ${suiteOptions} ${suiteRunSetOptions}"
              if $useSuitesOption; then
                resmokeParams="${resmokeParams} --suites=${suite}"
              fi
              runResmoke "${resmokeParams}" "$logOutputFile" "${suiteRawName}"
            fi
          done
          ;;
        *)
          echo "failed: Unknown runSet definition: ${suiteRunSet} for ${suite}" | tee -a "resmoke_unknown_${trial}.log"
          ;;
      esac

    fi

    ((suiteElementNumber++))

  done

done

echo "Generating summary:"

# shellcheck disable=SC2016
find . -type f \( -name "*_${trial}.log" -and -not -name "resmoke_summary_${trial}.log" \) \
  -exec grep -q ' Summary of ' {} \; \
  -print \
  -exec perl -ne 'chomp;$last=$this;$this=$_;if(m/^\[resmoke\].* Summary of /){$summ=1;printf "\t$last\n"};if(m/^Running:/){$summ=0;};if($summ){printf "\t$this\n"}' {} \; \
  | tee "resmoke_summary_${trial}.log"

