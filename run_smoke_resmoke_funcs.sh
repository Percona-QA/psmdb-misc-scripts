#!/bin/bash

# these are common functions used in the run_smoke_psmdb_3.0.sh and 
# run_resmoke_psmdb_3.2.sh scripts

# constants
ULIMIT_NOFILES_MINIMUM=64000
ULIMIT_UPROCS_MINIMUM=64000
DBPATH="/data"   # don't change there are some hard codings

run_system_validations() {

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

  # check for needed mongo binaries

  for binary in mongo mongod mongos; do
    if [ ! -x "./${binary}" ]; then
      echo "Could not find ./${binary}; make sure you are running this from the root build directory,"
      echo "and that the MongoDB binaries have been built."
      exit 1;
    fi
  done

  for binary in bsondump mongodump mongoexport mongofiles mongoimport mongooplog mongorestore mongostat; do
    if [ ! -x "${MONGOTOOLS}/${binary}" ]; then
      echo "Could not find ${MONGOTOOLS}/${binary}; make sure the mongo-tools binaries have been built"
      echo "and can be found by the specified path."
      exit 1;
    fi
  done

  # check for keys and set perms

  if ! ls jstests/libs/key* > /dev/null 2>&1; then
    echo "Run from the root build directory."
    exit 1;
  fi
  chmod 400 jstests/libs/key*

  # check for dbpath

  if [[ ! -d "${DBPATH}" ]]; then
    echo "The smoke test dbpath ${DBPATH} could not be found.  Please create this"
    echo "data directory before running tests. (a symlink to another location is ok)"
    echo "for faster speeds, an SSD target is recommended."
    exit 1;
  fi

}

load_suite_set() {
  local basedir="$1"
  local suiteSet="$2"
  local file=""

  if [ -e "${basedir}/suite_sets/${suiteSet}" ]; then
    file="${basedir}/suite_sets/${suiteSet}";
  elif [ -e "${basedir}/suite_sets/${suiteSet}.txt" ]; then
    file="${basedir}/suite_sets/${suiteSet}.txt";
  elif [ -e "${suiteSet}" ]; then
    file="${suiteSet}"
  fi

  if [ -z "${file}" ]; then
    exit "Could not open suite set: ${suiteSet} (basedir: ${basedir}"
    exit 1
  fi

  readarray SUITES < "${file}"

}

detectEngines() {
  ENGINES=()
  DEFAULT_ENGINE=$(./mongod --help | grep storageEngine | perl -ne 'm/\(=([^\)]+)\)/;print $1')
  if [ "${DEFAULT_ENGINE}" == "" ]; then
    DEFAULT_ENGINE="wiredTiger"
  fi

  ENGINES+=(${DEFAULT_ENGINE})
  for engine in mmapv1 wiredTiger PerconaFT rocksdb inMemory; do
    if [ ! "${engine}" == "${DEFAULT_ENGINE}" ]; then
      if ./mongod --help | grep -q "${engine}" || [ "${engine}" = "mmapv1" ]; then
        ENGINES+=("${engine}")
      fi
    fi
  done
}

hasEngine() {
  if [ ${#ENGINES[@]} -eq 0 ]; then
    detectEngines
  fi

  local engine
  for engine in "${ENGINES[@]}"; do [[ "$engine" == "$1" ]] && return 0; done
  return 1
}

runPreprocessingCommands() {
  local logOutputFile=$1
  local suiteRawName=$2
  local foundCommandSuite=false

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

}


