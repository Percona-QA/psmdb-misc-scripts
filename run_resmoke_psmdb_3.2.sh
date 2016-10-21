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

# smoke parameters
RESMOKE_JOBS=$(grep -cw ^processor /proc/cpuinfo)
RESMOKE_BASE="--continueOnFailure --jobs=${RESMOKE_JOBS} --shuffle"
RESMOKE_DEFAULT=""
RESMOKE_AUTH="--auth"
RESMOKE_SE=""

# trial number

if [ "$1" == "" ]; then
  echo "Usage ../psmdb-misc-scripts/run_resmoke_psmdb_3.2.sh [trial #] {suite set}"
  echo "Where:"
  echo -e "\t[trial #] is a unique label for this trial test (ex. 20160901_3.2.8_01 )"
  echo -e "\t{suite set} is an optional name of suite sets to run (see psmdb-misc-scripts/suite_sets)"
  echo -e "\t\tdefault suite set is: resmoke_psmdb_3.2_default.txt"
  echo -e "\t\tif the suite set is not found in psmdb-misc-scripts/suite_sets"
  echo -e "\t\tthen script will attempt to load as absolute path."
  exit 1;
fi
trial=$1

run_system_validations

# read suite sets

if [ -z "$2" ]; then
  suiteSet="resmoke_psmdb_3.2_default.txt"
else
  suiteSet="$2"
fi
# returns SUITES
load_suite_set "${basedir}" "${suiteSet}"

# main script

runResmoke() {
  local resmokeParams=$1
  local logOutputFile=$2
  local suiteRawName=$3

  rm -rf "${DBPATH}/*"

  runPreprocessingCommands "${logOutputFile}" "${suiteRawName}"

  # add json output if it's not there
  if [[ ${resmokeParams} != *"reportFile"* ]]; then
    resmokeParams="${resmokeParams} --reportFile=${logOutputFile%.*}.json"
  fi

  echo "Trial: ${trial}" | tee -a "${logOutputFile}"
  echo "Base Directory: ${basedir}" | tee -a "${logOutputFile}"
  echo "Suite Set: ${suiteSet}" | tee -a "${logOutputFile}"

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

          detectEngines

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

