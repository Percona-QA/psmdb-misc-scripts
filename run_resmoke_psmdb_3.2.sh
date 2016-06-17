#!/bin/bash

# Run resmoke test suites for PSMDB 3.2 

# constants
ULIMIT_NOFILES_MINIMUM=64000
ULIMIT_UPROCS_MINIMUM=64000
DBPATH="/data"   # don't change there are some hard codings

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
auth,mmapv1,wiredTiger,PerconaFT,rocksdb
bulk_gle_passthrough,mmapv1,wiredTiger,PerconaFT,rocksdb
concurrency,mmapv1,wiredTiger,PerconaFT,rocksdb
concurrency_replication,mmapv1,wiredTiger,PerconaFT,rocksdb
concurrency_sharded,mmapv1,wiredTiger,PerconaFT,rocksdb
concurrency_sharded_sccc,mmapv1,wiredTiger,PerconaFT,rocksdb
!concurrency_simultaneous --executor=concurrency jstests/concurrency/fsm_all_simultaneous.js,mmapv1,wiredTiger,PerconaFT,rocksdb
dbtest,mmapv1,wiredTiger,PerconaFT,rocksdb
disk,default
dur_jscore_passthrough,default
durability,default,default
failpoints,default
failpoints_auth,default
gle_auth --shellWriteMode=legacy --shellReadMode=legacy,mmapv1,wiredTiger,PerconaFT,rocksdb
gle_auth_basics_passthrough --shellWriteMode=legacy --shellReadMode=legacy,mmapv1,wiredTiger,PerconaFT,rocksdb
gle_auth_basics_passthrough_write_cmd --suites=gle_auth_basics_passthrough --shellWriteMode=commands,mmapv1,wiredTiger,PerconaFT,rocksdb
gle_auth_write_cmd --shellWriteMode=commands,mmapv1,wiredTiger,PerconaFT,rocksdb
core,mmapv1,wiredTiger,PerconaFT,rocksdb
core_auth,default
core_compatibility --shellReadMode=legacy --shellWriteMode=compatibility,mmapv1,wiredTiger,PerconaFT,rocksdb
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
noPassthrough,mmapv1,wiredTiger,PerconaFT,rocksdb
noPassthroughWithMongod,mmapv1,wiredTiger,PerconaFT,rocksdb
parallel,mmapv1,wiredTiger,PerconaFT,rocksdb
parallel_compatibility --suites=parallel --shellReadMode=legacy --shellWriteMode=compatibility,mmapv1,wiredTiger,PerconaFT,rocksdb
replica_sets,mmapv1,wiredTiger,PerconaFT,rocksdb
replica_sets_auth,default
replication,mmapv1,wiredTiger,PerconaFT,rocksdb
replication_auth,default
sharding,mmapv1,wiredTiger,PerconaFT,rocksdb
sharding_auth,default
sharding_gle_auth_basics_passthrough --shellWriteMode=legacy --shellReadMode=legacy,mmapv1,wiredTiger,PerconaFT,rocksdb
sharding_gle_auth_basics_passthrough_write_cmd --suites=sharding_gle_auth_basics_passthrough --shellWriteMode=commands,mmapv1,wiredTiger,PerconaFT,rocksdb
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

### validations and fixes

# ulimit

ulimit_nofiles=$(ulimit -n)
[ "${ulimit_nofiles}" -lt "${ULIMIT_NOFILES_MINIMUM}" ] && {
  echo "Please increase this number of open files limit before running."
  echo "It should be equal to or greater than: ${ULIMIT_NOFILES_MINIMUM}."
  echo "The current setting is ${ulimit_nofiles}."
  exit 1;
}

ulimit_uprocs=$(ulimit -u)
[ "${ulimit_uprocs}" -lt "${ULIMIT_UPROCS_MINIMUM}" ] && {
  echo "Please increase this number of user processes  limit before running."
  echo "It should be equal to or greater than: ${ULIMIT_UPROCS_MINIMUM}"
  echo "The current setting is ${ulimit_uprocs}."
  exit 1;
}

# check for keys and set perms

if ! ls jstests/libs/key* > /dev/null 2>&1; then
  echo "Run from the root build directory."
  exit 1;
fi
chmod 400 jstests/libs/key*

# check for needed mongo binaries

for binary in bsondump mongo mongod mongodump mongoexport mongofiles mongoimport mongooplog mongorestore mongos mongostat; do
  if [ ! -x "./${binary}" ]; then
    echo "Could not find ./${binary}; make sure you are running this from the root build directory,"
    echo "that the MongoDB binaries have been built and the mongo-tools binaries have been copied"
    echo "to the build root."
    exit 1;
  fi
done

# check for dbpath

if [[ ! -d "${DBPATH}" ]]; then
  echo "The smoke test dbpath ${DBPATH} could not be found.  Please create this"
  echo "data directory before running tests. (a symlink to another location is ok)"
  echo "for faster speeds, an SSD target is recommended."
  exit 1;
fi

# trial number

if [ "$1" == "" ]; then
  echo "Usage ./run_smoke.sh {trial #}"
  exit 1;
fi
trial=$1

# detect available engines

ENGINES=()
DEFAULT_ENGINE="wiredTiger"
ENGINES+=(${DEFAULT_ENGINE})
for engine in mmapv1 wiredTiger PerconaFT rocksdb; do
  if [ ! "${engine}" == "${DEFAULT_ENGINE}" ]; then
    if ./mongod --help | grep -q "${engine}" || [ "${engine}" = "mmapv1" ]; then
      ENGINES+=("${engine}")
    fi
  fi
done

# main script

runResmoke() {
  local resmokeParams=$1
  local logOutputFile=$2
  local suiteRawName=$3
  local foundCommandSuite=false

  # look for preprocessing commands

  (
    for suiteCommand in "${SUITES[@]}"; do

      if ! ${foundCommandSuite} && [[ "${suiteCommand}" =~ ^[[:space:]]*\$ ]]; then
        continue
      fi

      if ${foundCommandSuite}; then
        if [[ "${suiteCommand}" =~ ^[[:space:]]*\$ ]]; then
          # shellcheck disable=SC2001
          preprocessingCommand=$(echo "${suiteCommand}" | sed 's/^\s*\$//')
          echo "Running: ${preprocessingCommand}" | tee -a "${logOutputFile}"
          # if export builtin is piped it will fail
          if [[ "${preprocessingCommand}" == *export* ]]; then
            eval "${preprocessingCommand}"
          else
            eval "${preprocessingCommand}" 2>&1 | tee -a "${logOutputFile}"
          fi
          continue
        else
          break
        fi
      fi

      IFS=',' read -r -a suiteDefinition <<< "${suiteCommand}"
      suiteName="${suiteDefinition[0]}"
      if [ "${suiteName}" = "${suiteRawName}" ]; then
        foundCommandSuite=true
        continue
      else
        foundCommandSuite=false
      fi

    done

    echo "Running: buildscripts/resmoke.py ${resmokeParams}" | tee -a "${logOutputFile}" 
    # shellcheck disable=SC2086
    python buildscripts/resmoke.py ${resmokeParams} 2>&1 | tee -a "${logOutputFile}"
  )

}

hasEngine() {
  local engine
  for engine in "${ENGINES[@]}"; do [[ "$engine" == "$1" ]] && return 0; done
  return 1
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
      logOutputFilePrefix="resmoke_${suite}_${suiteRunSet}"

      case "$suiteRunSet" in

        "default"|"auth")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
          [ "${suiteRunSet}" == "default" ] && resmokeParams=${RESMOKE_DEFAULT}
          [ "${suiteRunSet}" == "auth" ] && resmokeParams=${RESMOKE_AUTH}
          resmokeParams="${RESMOKE_BASE} ${resmokeParams} ${suiteOptions} ${suiteRunSetOptions}"
          if $useSuitesOption; then
            resmokeParams="${resmokeParams} --suites=${suite}"
          fi
          runResmoke "${resmokeParams}" "$logOutputFile" "${suiteRawName}"

          ;;
        "wiredTiger"|"PerconaFT"|"rocksdb"|"mmapv1")
          logOutputFile="${logOutputFilePrefix}_${trial}.log"
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
find . -type f -name "*_${trial}.log" \
  -exec grep -q ' Summary of ' {} \; \
  -print \
  -exec perl -ne 'chomp;$last=$this;$this=$_;if(m/^\[resmoke\].* Summary of /){$summ=1;printf "\t$last\n"};if(m/^Running:/){$summ=0;};if($summ){printf "\t$this\n"}' {} \; \
  > "resmoke_summary_${trial}.log"

